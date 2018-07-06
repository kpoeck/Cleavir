(cl:in-package #:cleavir-load-time-value-hoisting)

;;; A constructor is an object that describes how a load-time-value form or
;;; a literal object can be evaluated or reconstructed at load time.

(defclass constructor ()
  (;; There must not be circular references within creation forms.  We use
   ;; this boolean to detect such circularities.  Its value is NIL while
   ;; processing the dependencies of the current creation form and T once
   ;; all creation form dependencies have been processed.
   (%creation-form-finalized-p :initform nil :accessor creation-form-finalized-p)
   (%creation-form :initform nil :initarg :creation-form :reader creation-form)
   (%initialization-form :initform nil :initarg :initialization-form :reader initialization-form)
   (%creation-thunk :accessor creation-thunk)
   (%initialization-thunk :accessor initialization-thunk)))

(defmethod make-constructor (object system)
  (multiple-value-bind (creation-form initialization-form)
      (make-load-form object *compilation-environment*)
    (make-instance 'constructor
      :creation-form creation-form
      :initialization-form initialization-form)))

(defmethod make-constructor ((input cleavir-ir:load-time-value-input) system)
  (break)
  (make-instance 'constructor
    :creation-form (cleavir-ir:form input)))

(defmethod make-constructor ((input cleavir-ir:constant-input) system)
  (ensure-constructor (cleavir-ir:value input) system))

(defmethod make-constructor ((ratio ratio) system)
  (make-instance 'constructor
    :creation-form
    `(/ ',(numerator ratio)
        ',(denominator ratio))))

(defmethod make-constructor ((complex complex) system)
  (make-instance 'constructor
    :creation-form
    `(complex ',(realpart complex)
              ',(imagpart complex))))

(defmethod make-constructor ((cons cons) system)
  (make-instance 'constructor
    :creation-form `(cons nil nil)
    :initialization-form
    `(setf (car ,cons) ',(car cons)
           (cdr ,cons) ',(cdr cons))))

(defmethod make-constructor ((symbol symbol) system)
  (make-instance 'constructor
    ;; We have a problem here - the CAR of the creation form is itself a
    ;; symbol, leading to a circular creation form.  Systems need to
    ;; provide a custom method for symbols to avoid this case.
    :creation-form
    `(intern ',(symbol-name symbol)
             ',(symbol-package symbol))))

(defmethod make-constructor ((package package) system)
  (make-instance 'constructor
    :creation-form
    `(or (find-package ',(package-name package))
         (error "There is no package named ~A."
                ,(package-name package)))))

(defmethod make-constructor ((array array) system)
  (make-instance 'constructor
    :creation-form
    `(make-array
      ',(array-dimensions array)
      :element-type ',(array-element-type array))
    :initialization-form
    `(progn ,@(loop for index below (array-total-size array)
                    collect
                    `(setf (row-major-aref ,array ,index)
                           ',(row-major-aref array index))))))

(defmethod make-constructor ((hash-table hash-table) system)
  (make-instance 'constructor
    :creation-form
    `(make-hash-table :test ',(hash-table-test hash-table)
                      :size ',(hash-table-size hash-table))
    :initialization-form
    `(progn ,@(maphash
               (lambda (key value)
                 `(setf (gethash ,key ,hash-table) ',value))
               hash-table))))
