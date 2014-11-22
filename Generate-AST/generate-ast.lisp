(in-package #:cleavir-generate-ast)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting code to an abstract syntax tree.

;;; The main entry point for converting a form.
(defgeneric convert (form environment))

;;; Utility function for converting a sequence of forms, represented
;;; as a list.
(defun convert-sequence (forms environment)
  (loop for form in forms
	collect (convert form environment)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Converting a compound form when the head of a compound form is a
;;; CONS.  Then the head must be a lambda expression.  We replace a
;;; call such as ((lambda (params) . body) . args) by (flet ((temp
;;; (params) . body)) (temp . args))
;;;
;;; FIXME: do some more error checking.
(defun convert-lambda-call (form env)
  (destructuring-bind ((lambda lambda-list &rest body) &rest args) form
    (declare (ignore lambda))
    (cleavir-ast:make-call-ast
     (convert-code lambda-list body env)
     (convert-sequence args env))))

(defun add-lambda-list-to-env (lambda-list env)
  (let ((rest lambda-list)
	(new-env env))
    (tagbody
     required
       (cond ((null rest) (go out))
	     ((eq (car rest) '&optional) (pop rest) (go optional))
	     ((eq (car rest) '&key) (pop rest) (go key))
	     (t (let* ((var (pop rest))
		       (var-ast (cleavir-ast:make-lexical-ast var)))
		  (setq new-env
			(cleavir-env:add-lexical-variable
			 new-env var var-ast)))
		(go required)))
     optional
       (cond ((null rest) (go out))
	     ((eq (car rest) '&key) (pop rest) (go key))
	     (t (let* ((var1 (first (first rest)))
		       (var1-ast (cleavir-ast:make-lexical-ast var1))
		       (var2 (second (first rest)))
		       (var2-ast (cleavir-ast:make-lexical-ast var2)))
		  (setq new-env
			(cleavir-env:add-lexical-variable
			 new-env var1 var1-ast))
		  (setq new-env
			(cleavir-env:add-lexical-variable
			 new-env var2 var2-ast)))
		(pop rest)
		(go optional)))
     key
       (cond ((or (null rest) (eq (car rest) '&allow-other-keys))
	      (go out))
	     (t (let* ((var1 (second (first rest)))
		       (var1-ast (cleavir-ast:make-lexical-ast var1))
		       (var2 (third (first rest)))
		       (var2-ast (cleavir-ast:make-lexical-ast var2)))
		  (setq new-env
			(cleavir-env:add-lexical-variable
			 new-env var1 var1-ast))
		  (setq new-env
			(cleavir-env:add-lexical-variable
			 new-env var2 var2-ast)))
		(pop rest)
		(go key)))
     out)
    new-env))

(defun var-to-lexical-identity (var env)
  (let ((info (cleavir-env:variable-info env var)))
    (cleavir-env:identity info)))

(defun build-ast-lambda-list (lambda-list env)
  (let ((rest lambda-list)
	(result nil))
    (tagbody
     required
       (cond ((null rest)
	      (go out))
	     ((eq (car rest) '&optional)
	      (push (pop rest) result)
	      (go optional))
	     ((eq (car rest) '&key)
	      (push (pop rest) result)
	      (go key))
	     (t (push (var-to-lexical-identity (pop rest) env) result)
		(go required)))
     optional
       (cond ((null rest)
	      (go out))
	     ((eq (car rest) '&key)
	      (push (pop rest) result)
	      (go key))
	     (t (push (list (var-to-lexical-identity (first (first rest)) env)
			    (var-to-lexical-identity (second (first rest)) env))
		      result)
		(pop rest)
		(go optional)))
     key
       (cond ((null rest)
	      (go out))
	     ((eq (car rest) '&allow-other-keys)
	      (push '&allow-other-keys result))
	     (t (push (list (first (first rest))
			    (var-to-lexical-identity (second (first rest)) env)
			    (var-to-lexical-identity (third (first rest)) env))
		      result)
		(pop rest)
		(go key)))
     out)
    (nreverse result)))

;;; ENV is an environment that is known to contain information about
;;; the variable VARIABLE, but we don't know whether it is special or
;;; lexical.  VALUE-AST is an AST that computes the value to be given
;;; to VARIABLE.  NEXT-AST is an AST that represents the computation
;;; to take place after the variable has been given its value.  If the
;;; variable is special, this function creates a BIND-AST with
;;; NEXT-AST as its body.  If the variable is lexical, this function
;;; creates a PROGN-AST with two ASTs in it.  The first one is a
;;; SETQ-AST that assigns the value to the variable, and the second
;;; one is the NEXT-AST.
(defun set-or-bind-variable (variable value-ast next-ast env)
  (let ((info (cleavir-env:variable-info env variable)))
    (assert (not (null info)))
    (if (typep info 'cleavir-env:special-variable-info)
	(cleavir-ast:make-bind-ast variable value-ast next-ast)
	(cleavir-ast:make-progn-ast
	 (list (cleavir-ast:make-setq-ast
		(cleavir-env:identity info)
		value-ast)
	       next-ast)))))

(defun process-remaining-aux (aux dspecs forms env)
  (if (null aux)
      (cleavir-ast:make-progn-ast (convert-sequence forms env))
      (destructuring-bind (var init) (first aux)
	(let* ((new-env (augment-environment-with-variable
			 var dspecs env env))
	       (value-ast (convert init env))
	       (next-ast (process-remaining-aux (rest aux) dspecs forms new-env)))
	  (set-or-bind-variable var value-ast next-ast new-env)))))

(defun process-aux (parsed-lambda-list dspecs forms env)
  (let ((aux (cleavir-code-utilities:aux parsed-lambda-list)))
    (if (eq aux :none)
	(cleavir-ast:make-progn-ast (convert-sequence forms env))
	(process-remaining-aux aux dspecs forms env))))

;;; VAR-AST and SUPPLIED-P-AST are LEXICAL-ASTs that will be set by
;;; the implementation-specific argument-parsing code, according to
;;; what arguments were given.  VALUE-AST is an AST that computes the
;;; initialization for of the variable.  This function generates the
;;; code for testing whether SUPPLIED-P-AST computes NIL or T, and for
;;; assigning the value computed by VALUE-AST to VAR-AST if
;;; SUPPLIED-P-AST computes NIL.
(defun generate-initialization (var-ast supplied-p-ast value-ast)
  (cleavir-ast:make-if-ast
   (cleavir-ast:make-eq-ast
    supplied-p-ast
    (cleavir-ast:make-constant-ast nil))
   (cleavir-ast:make-setq-ast var-ast value-ast)
   (cleavir-ast:make-constant-ast nil)))

;;; VAR and SUPPLIED-P are symbols representing a parameter variable
;;; and its associated SUPPLIED-P variable. If no associated
;;; SUPPLIED-P variable is present in the lambda list then SUPPLIED-P
;;; is NIL.  INIT-FORM is the form to be assigned to VAR if no
;;; argument was supplied for it.  DSPECS is a list of canonicalized
;;; declarations specifiers, and is used together with ENV to
;;; determine whether VAR and/or SUPPLIED-P are special variables.
;;; ENV is the environment in which this parameter is to be processed.
;;; NEXT-AST is an AST that represents the computation to follow this
;;; one.
;;;
;;; This function returns two values.  The first value is an AST that
;;; represents both the processing of this parameter AND the
;;; computation that follows.  We can not return an AST only for this
;;; computation, because if either VAR or SUPPLIED-P is special, then
;;; NEXT-AST must be in the body of a BIND-AST generated by this
;;; function.  The second return value is a list of two LEXICAL-ASTs.
;;; The first lexical AST corresponds to VAR and the second to
;;; SUPPLIED-P.  The implementation-specific argument-parsing code is
;;; responsible for assigning to those LEXICAL-ASTs according to what
;;; arguments were given to the function.
(defun process-init-parameter (var supplied-p init-form dspecs env next-ast)
  (let ((new-env (augment-environment-with-variable var dspecs env env))
	(lexical-var-ast (cleavir-ast:make-lexical-ast var))
	(lexical-supplied-p-ast (cleavir-ast:make-lexical-ast supplied-p)))
    (unless (null supplied-p)
      (setf new-env
	    (augment-environment-with-variable
	     supplied-p dspecs new-env new-env)))
    (values (cleavir-ast:make-progn-ast
	     (list (generate-initialization lexical-var-ast
					    lexical-supplied-p-ast
					    (convert init-form env))
		   (set-or-bind-variable
		    var
		    lexical-var-ast
		    (if (null supplied-p)
			next-ast
			(set-or-bind-variable
			 supplied-p
			 lexical-supplied-p-ast
			 next-ast
			 new-env))
		    new-env)))
	    (list lexical-var-ast lexical-supplied-p-ast))))

(defun process-allow-other-keys (parsed-lambda-list dspecs forms env)
  (multiple-value-bind (ast lexicals)
      (process-aux parsed-lambda-list dspecs forms env)
    (values ast
	    (if (cleavir-code-utilities:allow-other-keys parsed-lambda-list)
		(cons '&allow-other-keys lexicals)
		lexicals))))

(defun augment-environment-with-parameter (var supplied-p dspecs env)
  (let ((new-env (augment-environment-with-variable
		  var dspecs env env)))
    (if (null supplied-p)
	new-env
	(augment-environment-with-variable supplied-p dspecs new-env new-env))))

(defun process-remaining-keys (keys parsed-lambda-list dspecs forms env)
  (if (null keys)
      (values (process-allow-other-keys parsed-lambda-list dspecs forms env)
	      '())
      (destructuring-bind ((keyword var) init &optional supplied-p)
 	  (first keys)
	(let ((new-env (augment-environment-with-parameter
			var supplied-p dspecs env)))
	  (multiple-value-bind (next-ast next-lexical-parameters)
	      (process-remaining-keys (rest keys)
				      parsed-lambda-list
				      dspecs
				      forms
				      new-env)
	    (multiple-value-bind (ast lexical-locations)
		(process-init-parameter var supplied-p init dspecs env next-ast)
	      (values ast
		      (cons (cons keyword lexical-locations)
			    next-lexical-parameters))))))))

(defun process-keys (parsed-lambda-list dspecs forms env)
  (let ((keys (cleavir-code-utilities:keys parsed-lambda-list)))
    (if (eq keys :none)
	(process-aux parsed-lambda-list dspecs forms env)
	(multiple-value-bind (ast lexicals)
	    (process-remaining-keys keys parsed-lambda-list dspecs forms env)
	  (values ast (cons '&key lexicals))))))

(defun process-rest (parsed-lambda-list dspecs forms env)
  (let ((rest (cleavir-code-utilities:rest-body parsed-lambda-list)))
    (if (eq rest :none)
	(process-keys parsed-lambda-list dspecs forms env)
	(let ((new-env (augment-environment-with-variable rest dspecs env env)))
	  (multiple-value-bind (next-ast next-lexical-parameters)
	      (process-keys parsed-lambda-list
			    dspecs
			    forms
			    new-env)
	    (let ((lexical-ast (cleavir-ast:make-lexical-ast rest)))
	      (values (set-or-bind-variable rest lexical-ast next-ast new-env)
		      (list* '&rest lexical-ast next-lexical-parameters))))))))

(defun process-remaining-optionals (optionals parsed-lambda-list dspecs forms env)
  (if (null optionals)
      (process-rest parsed-lambda-list dspecs forms env)
      (destructuring-bind (var init &optional supplied-p)
 	  (first optionals)
	(let ((new-env (augment-environment-with-parameter
			var supplied-p dspecs env)))
	  (multiple-value-bind (next-ast next-lexical-parameters)
	      (process-remaining-optionals (rest optionals)
					   parsed-lambda-list
					   dspecs
					   forms
					   new-env)
	    (multiple-value-bind (ast lexical-locations)
		(process-init-parameter var supplied-p init dspecs env next-ast)
	      (values ast
		      (cons lexical-locations next-lexical-parameters))))))))

(defun process-optionals (parsed-lambda-list dspecs forms env)
  (let ((optionals (cleavir-code-utilities:optionals parsed-lambda-list)))
    (if (eq optionals :none)
	(process-keys parsed-lambda-list dspecs forms env)
	(multiple-value-bind (ast lexicals)
	    (process-remaining-optionals optionals
					 parsed-lambda-list
					 dspecs
					 forms
					 env)
	  (values ast (cons '&optional lexicals))))))

(defun process-required (required parsed-lambda-list dspecs forms env)
  (if (null required)
      (process-optionals parsed-lambda-list dspecs forms env)
      (let* ((var (first required))
	     (lexical-ast (cleavir-ast:make-lexical-ast var))
	     (new-env (augment-environment-with-variable
		       var dspecs env env)))
	(multiple-value-bind (next-ast next-lexical-parameters)
	    (process-required (rest required)
			      parsed-lambda-list
			      dspecs
			      forms
			      new-env)
	  (values (set-or-bind-variable var lexical-ast next-ast new-env)
		  (cons lexical-ast next-lexical-parameters))))))

(defun convert-code (lambda-list body env)
  (let ((parsed-lambda-list
	  (cleavir-code-utilities:parse-ordinary-lambda-list lambda-list)))
    (multiple-value-bind (declarations documentation forms)
	(cleavir-code-utilities:separate-function-body body)
      ;; FIXME: Handle documentation
      (declare (ignore documentation))
      (let ((canonicalized-declaration-specifiers
	      (cleavir-code-utilities:canonicalize-declaration-specifiers
	       (reduce #'append (mapcar #'cdr declarations)))))
	(multiple-value-bind (ast lexical-lambda-list)
	    (process-required (cleavir-code-utilities:required parsed-lambda-list)
			      parsed-lambda-list
			      canonicalized-declaration-specifiers
			      forms
			      env)
	  (cleavir-ast:make-function-ast ast lexical-lambda-list))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; CONVERT-FORM is called by CONVERT when the form is either a symbol
;;; or a CONS with a symbol in the CAR.  It is called with three
;;; arguments: 1. the form;  2. the environment INFO resulting from
;;; calling VARIABLE-INFO on the symbol or from calling FUNCTION-INFO
;;; on the CAR of the CONS;  3. the environment.

(defgeneric convert-form (form info environment))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; CONVERT is responsible for converting a form to an abstract syntax
;;; tree.

(defmethod convert (form environment)
  (cond ((and (not (consp form)) (not (symbolp form)))
	 (cleavir-ast:make-constant-ast form))
	((and (symbolp form) (constantp form))
	 (cleavir-ast:make-constant-ast (symbol-value form)))
	((symbolp form)
	 (let ((info (variable-info environment form)))
	   (convert-form form info environment)))
	((symbolp (car form))
	 (let ((info (function-info environment (car form))))
	   (convert-form form info environment)))
	(t
	 (convert-lambda-call form environment))))

(defun generate-ast (form environment)
  (convert form environment))

;;; This variable should be bound by client code to one of the symbols
;;; CL:COMPILE, CL:COMPILE-FILE, or CL:EVAL before the main entry
;;; point is called.
(defvar *compiler*)

;;; This variable indicates whether a form should be evaluated in
;;; addition to be being processed by the compiler.
(defparameter *compile-time-too* nil)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Managing top-level forms.
;;;
;;; We need to be able to test whether a form is a top-level form or
;;; not.  A few special forms (LOCALLY, MACROLET, SYMBOL-MACROLET)
;;; preserve this property in that if the special form itself is a
;;; top-level form, then the body of the special form is also a
;;; top-level form.  For all other forms, any subform of the form is
;;; not considered a top-level form.

;;; This variable is true if and only if the form to be compiled is a
;;; top-level form.
(defparameter *top-level-form-p* t)

;;; The reason for the following somewhat twisted logic is that we
;;; want to avoid having to explicitly set *TOP-LEVEL-FORM-P* no false
;;; in every method EXCEPT the ones for LOCALLY, MACROLET, and
;;; SYMBOL-MACROLET.  This logic allows us to add some code ONLY to
;;; these special forms in order to indicate that they preserve the
;;; top-level property.
;;;
;;; The way this logic works is as follows: We define a second
;;; variable named *OLD-TOP-LEVEL-FORM-P*.  This variable holds the
;;; value of *TOP-LEVEL-FORM-P* as it was before CONVERT was called,
;;; and this is the variable that we actually test in order to
;;; determine whether a form is a top-level form.  To obtain that, we
;;; define an :AROUND method on CONVERT that binds
;;; *OLD-TOP-LEVEL-FORM-P* to the value of *TOP-LEVEL-FORM-P* for the
;;; duration of the invocation of the primary method on CONVERT, and
;;; that also binds *TOP-LEVEL-FORM-P* to false.  Any recursive
;;; invocation of CONVERT will thus automatically see the value of
;;; *OLD-TOP-LEVEL-FORM-P* as false.  The methods for LOCALLY,
;;; MACROLET, and SYMBOL-MACROLET set *OLD-TOP-LEVEL-FORM-P* to true
;;; so that when they recursively call CONVERT, then this true value
;;; will be the value of *OLD-TOP-LEVEL-FORM-P*.  I hope this
;;; explanation makes sense.

(defvar *old-top-level-form-p*)

(defmethod convert :around (form environment)
  (let ((*old-top-level-form-p* *top-level-form-p*)
	(*top-level-form-p* nil))
    (when (and *compile-time-too* *old-top-level-form-p*)
      (cleavir-env:eval form environment environment ))
    (call-next-method)))
