(in-package :xcb.clx.ext.glx)

(defstruct (context (:conc-name %context-)
                    (:constructor %make-context))
  (xlib-glx-ctx (null-pointer) :type #.(type-of (null-pointer))))

(defstruct (glx-window (:include xcb:window)
                       (:conc-name %glx-window-)
                       (:constructor %make-glx-window)))

 ;; Tables

(define-const-table *glx-table* ("GLX")
  :use-gl :buffer-size :level :rgba (:double-buffer :doublebuffer)
  :stereo :aux-buffers :red-size :green-size :blue-size :alpha-size
  :depth-size :stencil-size :accum-red-size :accum-green-size
  :accum-blue-size :accum-alpha-size

  :window-bit :pixmap-bit :pbuffer-bit :aux-buffers-bit
  :front-left-buffer-bit :front-right-buffer-bit
  :back-left-buffer-bit :back-right-buffer-bit
  :depth-buffer-bit :stencil-buffer-bit :accum-buffer-bit :none
  :slow-config :true-color :direct-color :pseudo-color :static-color
  :gray-scale :static-gray

  :drawable-type :render-type :x-renderable :x-visual-type
  :config-caveat :transparent-type

  :rgba-bit :color-index-bit

  :context-major-version-arb :context-minor-version-arb

  :visual-id)

(defmacro with-glx-attr ((ptr attr-list) &body body)
  (let ((list (gensym "LIST"))
        (len (gensym "LEN"))
        (i (gensym)) (attr (gensym)) (v (gensym)))
    `(let* ((,list ,attr-list)
            (,len (length ,list))
            (,i 0))
       (with-foreign-object (,ptr :int (1+ ,len))
         (dolist (,attr ,list)
           (let ((,v (etypecase ,attr
                       (boolean (if ,attr 1 0))
                       (symbol (cdr (assoc ,attr *glx-table*)))
                       (number ,attr))))
                 (setf (mem-aref ,ptr :int ,i) ,v)
                 (incf ,i)))
         (setf (mem-aref ,ptr :int ,i) +NONE+)
         ,@body))))

 ;; GL Context

;;;; The CLX interface for GLX isn't formally defined, but the
;;;; portable-clx implementation is defacto, so this attempts to mimic
;;;; it for compatibility.

(defun create-context (screen visual &optional share-list is-direct)
  (with-glx-attr (ptr '(:context-major-version-arb 3
                        :context-minor-version-arb 0))
    (let* ((dpy (xlib::%display-xlib-display
                 (xlib::%screen-display screen)))
           (vis (xcb::%x-ptr visual))
           (ptr (gl-xcreate-context dpy vis (or share-list (null-pointer))
                                    (if is-direct 1 0))))
      (if (null-pointer-p ptr)
          (error "Unable to create GLX context")
          (%make-context :xlib-glx-ctx ptr)))))

(defun create-context-arb (display fbconfig &optional share-list is-direct)
  (with-glx-attr (attr '(:context-major-version-arb 3
                         :context-minor-version-arb 0))
    (let* ((dpy (xlib::%display-xlib-display display))
           (fbptr (xcb::%x-ptr fbconfig))
           (ptr (gl-xcreate-context-attribs-arb
                 dpy (mem-ref fbptr :pointer)
                 (or share-list (null-pointer))
                 (if is-direct 1 0)
                 attr)))
      (if (null-pointer-p ptr)
          (error "Unable to create GLX context")
          (%make-context :xlib-glx-ctx ptr)))))

(defun create-new-context (display fbconfig &optional share-list is-direct)
    (let* ((dpy (xlib::%display-xlib-display display))
           (fbptr (xcb::%x-ptr fbconfig))
           (ptr (gl-xcreate-new-context
                 dpy (mem-ref fbptr :pointer)
                 +glx-rgba-type+
                 (or share-list (null-pointer))
                 (if is-direct 1 0))))
      (if (null-pointer-p ptr)
          (error "Unable to create GLX context")
          (%make-context :xlib-glx-ctx ptr))))

(defun destroy-context (ctx &optional (display *display*))
  (gl-xdestroy-context (xcb.clx::%display-xlib-display display)
                       (%context-xlib-glx-ctx ctx))
  (setf (%context-xlib-glx-ctx ctx) (null-pointer))
  (values))

(defun destroy-glx-window (window)
  (gl-xdestroy-window (xcb.clx::%display-xlib-display
                       (%glx-window-display window))
                      (%glx-window-id window)))

(defun make-current (drawable ctx)
  (let ((dpy (xlib::%display-xlib-display
              (xlib::%drawable-display drawable)))
        (id (xlib::%drawable-id drawable))
        (ptr (%context-xlib-glx-ctx ctx)))
    (gl-xmake-current dpy id ptr)))

(defun make-context-current (draw-drawable read-drawable ctx)
  (let ((dpy (xlib::%display-xlib-display
              (xlib::%drawable-display draw-drawable)))
        (did (xlib::%drawable-id draw-drawable))
        (rid (xlib::%drawable-id read-drawable))
        (ptr (%context-xlib-glx-ctx ctx)))
    (gl-xmake-context-current dpy did rid ptr)))

(defun choose-fbconfig (screen attrs)
  (with-glx-attr (ptr attrs)
    (with-foreign-object (nelements :int)
      (let* ((fbptr (gl-xchoose-fbconfig (xlib::%display-xlib-display
                                          (xlib::%screen-display screen))
                                         (xlib::%screen-number screen)
                                         ptr nelements))
             (fb (xcb::%make-x-ptr :ptr fbptr :type 'fbconfig)))
        (when (null-pointer-p fbptr)
          (error "Failed to choose FBConfig"))
        (tg:finalize fb (lambda () (xfree fbptr)))
        fb))))

(defun get-visual-from-fbconfig (display fbconfig)
  (let ((ptr (gl-xget-visual-from-fbconfig (xlib::%display-xlib-display
                                            display)
                                           (mem-ref (xcb::%x-ptr fbconfig)
                                                    :pointer))))
    (when (null-pointer-p ptr)
      (error "Unable to get visual from fbconfig ~A" fbconfig))
    (let ((vis (xcb::%make-x-ptr :ptr ptr :type 'x-visual-info)))
      (tg:finalize vis (lambda () (xfree ptr)))
      vis)))

(defun choose-visual (screen attrs)
  (let ((fbconfig (choose-fbconfig screen attrs)))
    (get-visual-from-fbconfig (xcb.clx::%screen-display screen)
                              fbconfig)))

(defun get-visualid-from-fbconfig (display fbconfig)
  (with-foreign-object (ptr :int)
    (gl-xget-fbconfig-attrib (xcb.clx::%display-xlib-display display)
                             (mem-ref (xcb::%x-ptr fbconfig) :pointer)
                             (cdr (assoc :visual-id *glx-table*))
                             ptr)
    (mem-ref ptr :int)))

(defun create-glx-window (display fbconfig window &optional attrs)
  (let ((dpy (xcb.clx::%display-xlib-display display))
        (fbptr (mem-ref (xcb::%x-ptr fbconfig) :pointer))
        (window (xcb.clx::%window-id window)))
    (let* ((wid (gl-xcreate-window dpy fbptr window
                                   (if attrs attrs (null-pointer))))
           (glxwin (%make-glx-window :display display :id wid)))
      (when (= 0 wid)
        (error "Unable to create GLX Window"))
      glxwin)))

(defun swap-buffers (display drawable)
  (let ((dpy (xcb.clx::%display-xlib-display display))
        (did (xlib::%drawable-id drawable)))
    (gl-xswap-buffers dpy did)))

(defun wait-gl () (gl-xwait-gl))
(defun wait-x () (gl-xwait-x))
