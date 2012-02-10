(in-package :xcb)

 ;; Basic wrapper for memory management

(defstruct (x-ptr-wrapper (:constructor %make-x-ptr)
                          (:conc-name %x-))
  (ptr (null-pointer) :type #.(type-of (null-pointer)))
  (type nil))

(defmethod print-object ((object x-ptr-wrapper) stream)
  (print-unreadable-object (object stream)
    (format stream "~A [xval] {#x~8,'0X}"
            (%x-type object)
            (pointer-address (%x-ptr object)))))


 ;; Avoid fatal X errors

(defcallback xlib-error-handler :int ((dpy :pointer) (err :pointer))
  (let ((errlen 128))
    (with-foreign-object (ptr :char errlen)
      (xget-error-text dpy (xerror-event-error-code err)
                       ptr errlen)
      (error "X Error: ~A" (foreign-string-to-lisp ptr)))))

(defcallback xlib-io-error-handler :int ((dpy :pointer))
  (declare (ignore dpy))
  (error "X IO Error"))
