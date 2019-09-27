;;;; Common utilities to help in building bots

(in-package :granolin)

;;; Logging Bot

(defclass message-log ()
  ((output
    :accessor output
    :initarg :output
    :initform (error "Message Log requires an output stream")
    :type stream
    :documentation "An output stream to which messages are logged."
    )))

(defun print-assoc (alist &optional (stream t))
  (loop :for (k . v) :in alist
        :do (format stream "~a: ~a~%" k v)))

(defmethod handle-event :after ((log message-log) (event timeline-event) &optional room)
  (print "Joined Room Message/Timeline Event" (output log))  
  (let ((fields `(("room" . ,room)
                  ("sender" . ,(sender event))
                  ("event type" . ,(event-type event))
                  ("message type" . ,(msg-type event))
                  ("messge body" . ,(msg-body event))
                  ("content" . ,(event-content event)))))
    (print-assoc fields (output log))
    (terpri (output log))))


(defmethod handle-event :after ((log message-log) (event room-state-event) &optional room)
  (print "Joined Room State Event" (output log))  
  (let ((fields `(("room" . ,room)
                  ("sender" . ,(sender event))
                  ("event type" . ,(event-type event))
                  ("state key" . ,(state-key event))
                  ("content" . ,(event-content event)))))
    (print-assoc fields (output log))
    (terpri (output log))))


(defmethod handle-event :after ((log message-log) (event invitation-event) &optional room)
  (print "Invitation Event" (output log))
  (let ((fields `(("room" . ,room)
                  ("sender" . ,(sender event))
                  ("event type" . ,(event-type event))
                  ("state key" . ,(state-key event))
                  ("content" . ,(event-content event)))))
    (print-assoc fields (output log))
    (terpri (output log))))


;;; A Room and User Directory Bot

(defclass server-room ()
  ((id :accessor room-id :initarg :id :initform (error "Must have a room-id"))
   (name :accessor room-name :initarg :name :initform "")
   (aliases :accessor room-aliases :initarg :aliases :initform nil)
   (members :accessor room-members :initarg :members :initform nil)))

(defclass server-directory ()
  ((directory-table
    :reader directory-table
    :initform (make-hash-table :test 'equal)
    :documentation "A table mapping room IDs to room struct instances.")))

(defun get-room (client room-id)
  "Get the SERVER-ROOM struct keyed by ROOM-ID, or return NIL."
  (gethash room-id (directory-table client)))


(defun update-room-name (client room-id name)
  (let ((room (get-room client room-id)))
    (if room
        (setf (room-name room) name)
        (setf room (make-instance 'server-room :id room-id :name name)))
    (setf (gethash room-id (directory-table client)) room)))

(defun update-room-member (client room-id member)
  (let ((room (get-room client room-id)))
    (if room
        (pushnew member (room-members room) :test #'equal)
        (setf room (make-instance 'server-room :id room-id :members (list member))))
    (setf (gethash room-id (directory-table client)) room)))

;; TODO
(defun update-room-aliases (client room-id member)
  (declare (ignore client room-id member)))

(defmethod handle-event :after
    ((client server-directory) (event room-state-event) &optional room-id)
  (cond
    ((string= "m.room.name" (event-type event))
     (update-room-name client room-id (room-name event)))

    ((string= "m.room.member" (event-type event))
     (update-room-member client room-id (sender event)))

    ((string= "m.room.aliases" (event-type event))
     (update-room-aliases client room-id (room-aliases event)))))


(defun name-of-room (client room-id)
  "Looks up the name of a room with ROOM-ID. Returns a string of NIL"
  (let ((room (get-room client room-id)))
    (when room (room-name room))))

(defun find-rooms-named (client name &key like full)
  "Looks up the room ID of rooms with the name NAME. If LIKE is T, then any room
  whose name contains the NAME as a substring is returned. If FULL is T, then
  the SERVER-ROOM structs themselves are returned."
  (with-slots (directory-table) client
    (loop :for room :being :the :hash-values :of directory-table
          :when (or (string-equal name (room-name room))
                    (and like (search name (room-name room) :test #'string-equal)))
            :collect (if full room (room-id room)))))

(defun client-contacts (client)
  "Returns a list of all users this client knows about."
  (let (contacts)
    (loop :for room :being :the :hash-values :of (directory-table client) :do
      (dolist (user (room-members room))
        (pushnew user contacts :test #'equal)))
    contacts))

(defun find-contact (client name &key like)
  "Finds a specific matrix ID by name. If LIKE is NIL, returns a string equal to
   NAME if this client has a contact with that NAME, or NIL otherwise. If LIKE
   is not NIL returns the first matrix ID found that contains NAME as a
   substring, or NIL if no such matrix ID is found."
  (find-if (lambda (contact)
             (or (equal name contact)
                 (and like (search name contact :test #'string-equal))))
        (client-contacts client)))

;;; Basic Joiner Bot

(defclass auto-joiner () ())

(defmethod handle-event :after ((client auto-joiner) (event invitation-event) &optional room-id)
  (when (equal "invite"
               (getf (event-content event) :|join_rule|))
    (join-room client room-id)))

