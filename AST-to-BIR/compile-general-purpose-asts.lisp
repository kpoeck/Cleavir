(in-package #:cleavir-ast-to-bir)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; COMPILE-FUNCTION

(defun translate-lambda-list (lambda-list funct)
  (loop with ll with alist
        for item in lambda-list
        do (cond ((member item lambda-list-keywords)
                  (push item ll))
                 ((consp item)
                  (let ((valarg (make-instance 'cleavir-bir:argument
                                  :rtype :object))
                        (parg (make-instance 'cleavir-bir:argument
                                :rtype :object)))
                    (if (= (length item) 3)
                        (let ((keyv (find-or-create-variable
                                     (second item)
                                     funct))
                              (predv (find-or-create-variable
                                      (third item)
                                      funct)))
                          (push (list (first item) valarg parg) ll)
                          (setf alist
                                (list* (cons keyv valarg)
                                       (cons predv parg)
                                       alist)))
                        (let ((keyv (find-or-create-variable
                                     (first item)
                                     funct))
                              (predv (find-or-create-variable
                                      (second item)
                                      funct)))
                          (push (list valarg parg) ll)
                          (setf alist
                                (list* (cons keyv valarg)
                                       (cons predv parg)
                                       alist))))))
                 (t (let ((v (find-or-create-variable item funct))
                          (a (make-instance 'cleavir-bir:argument
                               :rtype :object)))
                      (push a ll)
                      (push (cons v a) alist))))
        finally (return (values (nreverse ll) alist))))

(defun insert-initial-bindings (inserter map)
  (loop for (var . arg) in map
        for setq = (make-instance 'cleavir-bir:writevar
                     :outputs (list var) :inputs (list arg))
        do (insert inserter setq)))

(defmethod compile-function ((ast cleavir-ast:function-ast))
  (let* ((function (make-instance 'cleavir-bir:function
                     :name (cleavir-ast:name ast)
                     :docstring (cleavir-ast:docstring ast)
                     :original-lambda-list (cleavir-ast:original-lambda-list ast)
                     :origin (cleavir-ast:origin ast)))
         (inserter (make-instance 'inserter))
         (start (make-iblock inserter
                             :function function :dynamic-environment function)))
    (multiple-value-bind (ll alist)
        (translate-lambda-list (cleavir-ast:lambda-list ast) function)
      (setf (cleavir-bir:lambda-list function) ll
            (cleavir-bir:variables function) (apply #'cleavir-set:make-set
                                                    (mapcar #'car alist))
            (cleavir-bir:start function) start)
      (begin inserter start)
      (insert-initial-bindings inserter alist)
      (let ((rv (compile-ast (cleavir-ast:body-ast ast) inserter)))
        (cond
          ((eq rv :no-return)
           (setf (cleavir-bir:end function) nil))
          (t
           (setf (cleavir-bir:end function) (iblock inserter))
           (terminate inserter
                      (make-instance 'cleavir-bir:returni
                        :inputs (adapt inserter rv :multiple-values)))))))
    function))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; IF-AST

(defun compile-branch (inserter test-ast branch-asts)
  (let ((iblocks (compile-test-ast test-ast inserter)))
    (when (eq iblocks :no-return) (return-from compile-branch iblocks))
    (assert (= (length iblocks) (length branch-asts)))
    (let ((map (loop with r = nil
                     for iblock in iblocks
                     for ast in branch-asts
                     for ins = (make-instance 'inserter)
                     do (proceed ins iblock)
                        (let ((rv (compile-ast ast ins)))
                          (unless (eq rv :no-return)
                            (push (list ins (iblock ins) rv) r)))
                     finally (return (nreverse r)))))
      (case (length map)
        ((0) ; no branch returned, so neither do we
         :no-return)
        ((1) ; a single branch returned, so don't bother with a merge
         (destructuring-bind (_ block rv) (first map)
           (proceed inserter block)
           rv))
        (t ; multiple blocks, so we have to merge their results
         (let ((mergeb (make-iblock inserter)))
           (if (loop for (_0 _1 rv) in map
                     always (listp rv))
               ;; No multiple values, so we can phi these.
               (let* ((nrtypes (loop for (_0 _1 rv) in map
                                     maximizing (length rv)))
                      ;; FIXME: In the future we may have non-:objects.
                      ;; It would be nice to not force everything to be objects
                      ;; in that circumstance.
                      ;; (Presumably for non-matches we'd cast both to :object)
                      (rtypes (make-list nrtypes :initial-element :object))
                      (phis (loop repeat nrtypes
                                  collect (make-instance 'cleavir-bir:phi
                                            :iblock mergeb :rtype :object))))
                 (loop for (ins ib rv) in map
                       do (terminate
                           ins
                           (make-instance 'cleavir-bir:jump
                             :inputs (adapt ins rv rtypes)
                             :outputs (copy-list phis) :unwindp nil
                             :next (list mergeb))))
                 (setf (cleavir-bir:inputs mergeb) phis)
                 (begin inserter mergeb)
                 phis)
               ;; Dump everything into multiple-values.
               (let ((phi (make-instance 'cleavir-bir:phi
                            :iblock mergeb :rtype :multiple-values)))
                 (loop for (ins ib rv) in map
                       do (terminate
                           ins
                           (make-instance 'cleavir-bir:jump
                             :inputs (adapt ins rv :multiple-values)
                             :outputs (list phi) :unwindp nil
                             :next (list mergeb))))
                 (setf (cleavir-bir:inputs mergeb) (list phi))
                 (begin inserter mergeb)
                 phi))))))))

(defmethod compile-ast ((ast cleavir-ast:if-ast) inserter)
  (compile-branch inserter (cleavir-ast:test-ast ast)
                  (list (cleavir-ast:then-ast ast) (cleavir-ast:else-ast ast))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; BRANCH-AST

(defmethod compile-ast ((ast cleavir-ast:branch-ast) inserter)
  (compile-branch inserter (cleavir-ast:test-ast ast)
                  (append (cleavir-ast:branch-asts ast)
                          (list (cleavir-ast:default-ast ast)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; PROGN-AST

(defun compile-sequence-for-effect (asts inserter)
  (loop for sub in asts
        for rv = (compile-ast sub inserter)
        when (eq rv :no-return)
          return nil
        finally (return t)))

(defmethod compile-ast ((ast cleavir-ast:progn-ast) inserter)
  (let ((form-asts (cleavir-ast:form-asts ast)))
    (assert (not (null form-asts)))
    (let ((last (first (last form-asts)))
          (bl (butlast form-asts)))
      (if (compile-sequence-for-effect bl inserter)
          (compile-ast last inserter)
          :no-return))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; BLOCK-AST

(defun block-info (block-ast) (gethash block-ast *block-info*))
(defun (setf block-info) (new-info block-ast)
  (setf (gethash block-ast *block-info*) new-info))

(defun insert-unwind (inserter catch contvar dest &optional inputs outputs)
  (let* ((read (insert inserter (make-instance 'cleavir-bir:readvar
                                  :rtype :continuation :inputs (list contvar))))
         (uw (make-instance 'cleavir-bir:unwind
               :inputs (list* read inputs) :outputs outputs :catch catch
               :destination dest)))
    (adjoin-variable inserter contvar)
    (terminate inserter uw)
    (cleavir-set:nadjoinf (cleavir-bir:unwinds catch) uw)
    (cleavir-set:nadjoinf (cleavir-bir:entrances dest) (iblock inserter)))
  (values))

(defun delete-catch (catch contvar wcont function dynenv iblock)
  ;; Replace the catch with a jump to iblock.
  ;; We could actually replace the block boundary entirely - FIXME
  (cleavir-set:nremovef (cleavir-bir:variables function) contvar)
  (cleavir-bir:delete-instruction wcont)
  (cleavir-set:doset (sc (cleavir-bir:scope catch))
    (setf (cleavir-bir:dynamic-environment sc) dynenv))
  (cleavir-bir:replace-terminator
   (make-instance 'cleavir-bir:jump :inputs () :outputs () :next (list iblock))
   catch))

(defmethod compile-ast ((ast cleavir-ast:block-ast) inserter)
  (let* ((function (function inserter))
         (de (dynamic-environment inserter))
         (during (make-iblock inserter))
         (catch (make-instance 'cleavir-bir:catch :next (list during)))
         (contvar (make-instance 'cleavir-bir:variable
                    :name (cleavir-ast:name ast)
                    :binder catch :rtype :continuation))
         (wcont (make-instance 'cleavir-bir:writevar
                  :outputs (list contvar) :inputs (list catch))))
    (adjoin-variable inserter contvar)
    (setf (cleavir-bir:dynamic-environment during) catch)
    (terminate inserter catch)
    (begin inserter during)
    (insert inserter wcont)
    (setf (block-info ast) nil)
    (let* ((normal-rv (compile-ast (cleavir-ast:body-ast ast) inserter))
           (entrances (block-info ast))
           (map (if (eq normal-rv :no-return)
                    entrances
                    (list* (list (iblock inserter) function normal-rv)
                           entrances))))
      (case (length map)
        (0 ; nothing returns here. We can replace the catch with a jump
         (delete-catch catch contvar wcont function de during)
         :no-return)
        (1 ; only one
         (destructuring-bind (ib jfunct rv) (first map)
           (proceed inserter ib)
           (cond ((eq jfunct function)
                  ;; We can just continue on from wherever that jump would be.
                  (delete-catch catch contvar wcont function de during)
                  rv)
                 (t ;; have to unwind.
                  (cleavir-set:nadjoinf (cleavir-bir:variables function)
                                        contvar)
                  (let* ((after (make-iblock inserter
                                             :function function
                                             :dynamic-environment de))
                         (phi (make-instance 'cleavir-bir:phi
                                :rtype :multiple-values :iblock after)))
                    (insert-unwind inserter catch contvar after
                                   (adapt inserter rv :multiple-values)
                                   (list phi))
                    (push after (cdr (cleavir-bir:next catch)))
                    (cleavir-set:nadjoinf (cleavir-bir:predecessors after)
                                          (cleavir-bir:iblock catch))
                    (begin inserter after)
                    phi)))))
        (t
         ;; KLUDGE: We force everything into multiple values as clients may
         ;; not be able to nonlocal-return in other formats.
         ;; Should be customizable.
         (let* ((mergeb (make-iblock inserter
                                       :function function
                                       :dynamic-environment de))
                (phi (make-instance 'cleavir-bir:phi :rtype :multiple-values
                                    :iblock mergeb)))
           (setf (cleavir-bir:inputs mergeb) (list phi))
           (loop with catchp = nil
                 for (ib jfunct rv) in map
                 do (proceed inserter ib)
                    (cond
                      ((eq jfunct function)
                       (terminate
                        inserter
                        (make-instance 'cleavir-bir:jump
                          :inputs (adapt inserter rv :multiple-values)
                          :outputs (list phi) :unwindp t
                          :next (list mergeb))))
                      (t
                       (setf catchp t)
                       (insert-unwind inserter catch contvar mergeb
                                      (adapt inserter rv :multiple-values)
                                      (list phi))))
                 finally
                    (cond
                      (catchp
                       ;; we still need the catch, so note the merge block
                       (push mergeb (cdr (cleavir-bir:next catch)))
                       (cleavir-set:nadjoinf (cleavir-bir:predecessors mergeb)
                                             (cleavir-bir:iblock catch)))
                      (t
                       ;; catch unneeded, replace with jump
                       (delete-catch catch contvar wcont function de during))))
           (begin inserter mergeb)
           phi))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; RETURN-FROM-AST

(defmethod compile-ast ((ast cleavir-ast:return-from-ast) inserter)
  (let ((rv (compile-ast (cleavir-ast:form-ast ast) inserter)))
    (unless (eq rv :no-return)
      (push (list (iblock inserter) (function inserter) rv)
            (block-info (cleavir-ast:block-ast ast)))))
  ;; terminator is actually generated by block-ast compilation
  :no-return)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; TAGBODY-AST

(defun go-info (tag-ast)
  (gethash tag-ast *go-info*))

(defun (setf go-info) (new-info tag-ast)
  (setf (gethash tag-ast *go-info*) new-info))

;;; FIXME: We really oughta move this up to CST-to-AST
(defun parse-tagbody (items)
  (loop with state = #() ; not a go tag
        with prefix = nil
        with tags = nil ; alist of (tag-ast . asts)
        with current = nil ; list of non-tag asts
        for item in items
        if (typep item 'cleavir-ast:tag-ast)
          do (if (vectorp state)
                 (setf prefix (nreverse current))
                 (push (cons state (nreverse current)) tags))
             (setf current nil)
             (setf state item)
        else do (push item current)
        finally (if (vectorp state)
                    (setf prefix (nreverse current))
                    (push (cons state (nreverse current)) tags))
                (return (values prefix (nreverse tags)))))

(defmethod compile-ast ((ast cleavir-ast:tagbody-ast) inserter)
  (multiple-value-bind (prefix tags)
      (parse-tagbody (cleavir-ast:item-asts ast))
    ;; Special case: there are no tags.
    (when (null tags)
      (return-from compile-ast
        (if (compile-sequence-for-effect prefix inserter)
            ()
            :no-return)))
    ;; General case
    (let* ((old-dynenv (dynamic-environment inserter))
           (function (function inserter))
           (prefix-iblock (make-iblock inserter))
           (tag-iblocks
             (loop repeat (length tags) collecting (make-iblock inserter)))
           (catch (make-instance 'cleavir-bir:catch
                    :next (list* prefix-iblock tag-iblocks)))
           (contvar (make-instance 'cleavir-bir:variable
                      :binder catch :rtype :continuation))
           (wcont (make-instance 'cleavir-bir:writevar
                    :outputs (list contvar) :inputs (list catch))))
      ;; this is used to check whether the catch is actually necessary.
      (setf (go-info catch) nil)
      (adjoin-variable inserter contvar)
      (setf (cleavir-bir:dynamic-environment prefix-iblock) catch)
      (loop for (tag-ast) in tags
            for tag-iblock in tag-iblocks
            do (setf (cleavir-bir:dynamic-environment tag-iblock) catch
                     (go-info tag-ast)
                     (list catch tag-iblock function contvar)))
      (terminate inserter catch)
      (begin inserter prefix-iblock)
      (insert inserter wcont)
      (when (compile-sequence-for-effect prefix inserter)
        (terminate inserter (make-instance 'cleavir-bir:jump
                              :inputs () :outputs ()
                              :next (list (first tag-iblocks)))))
      (loop for (tag . body) in tags
            for (ib . rest) on tag-iblocks
            do (begin inserter ib)
            if (compile-sequence-for-effect body inserter)
              ;; Code continues onto the next tag, or out of the tagbody.
              do (let ((next
                         (if rest
                             (first rest)
                             (make-iblock inserter
                                          :dynamic-environment old-dynenv))))
                   (terminate inserter
                              (make-instance 'cleavir-bir:jump
                                :inputs () :outputs () :unwindp (not rest)
                                :next (list next)))
                   (unless rest
                     ;; Start on the block after the tagbody.
                     (begin inserter next)
                     ;; If there were no nonlocal unwinds, simplify.
                     (unless (go-info catch)
                       (delete-catch catch contvar wcont
                                     function old-dynenv prefix-iblock))
                     ;; We return no values.
                     (return-from compile-ast ())))
            else
              ;; Code doesn't return. If this is the last tag, that means the
              ;; tagbody doesn't either.
              do (unless rest
                   ;; If there were no nonlocal unwinds, simplify.
                   (unless (go-info catch)
                     (delete-catch catch contvar wcont
                                   function old-dynenv prefix-iblock))
                   (return-from compile-ast :no-return))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; GO-AST

(defmethod compile-ast ((ast cleavir-ast:go-ast) inserter)
  (destructuring-bind (catch iblock cfunction cvar)
      (go-info (cleavir-ast:tag-ast ast))
    (let ((function (function inserter)))
      (cond
        ((eq function cfunction)
         ;; local
         (terminate inserter (make-instance 'cleavir-bir:jump
                               :unwindp t :inputs () :outputs ()
                               :next (list iblock))))
        (t
         (setf (go-info catch) t)
         ;; nonlocal
         (insert-unwind inserter catch cvar iblock)))))
  :no-return)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; CALL-AST

(defun compile-arguments (arg-asts inserter)
  (loop for arg-ast in arg-asts
        for rv = (compile-ast arg-ast inserter)
        if (eq rv :no-return)
          return rv
        else collect (first (adapt inserter rv '(:object)))))

(defmethod compile-ast ((ast cleavir-ast:call-ast) inserter)
  (let* ((callee1 (compile-ast (cleavir-ast:callee-ast ast) inserter))
         (callee2 (if (eq callee1 :no-return)
                      (return-from compile-ast :no-return)
                      (first (adapt inserter callee1 '(:object)))))
         (args (compile-arguments (cleavir-ast:argument-asts ast) inserter)))
    (if (eq args :no-return)
        args
        (insert inserter (make-instance 'cleavir-bir:call
                           :inputs (list* callee2 args))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; FUNCTION-AST

(defmethod compile-ast ((ast cleavir-ast:function-ast) inserter)
  (let* ((f (or (gethash ast *function-info*)
                (setf (gethash ast *function-info*)
                      (compile-function ast))))
         (enclose (make-instance 'cleavir-bir:enclose :code f)))
    (cleavir-set:nadjoinf (cleavir-bir:encloses f) enclose)
    (list (insert inserter enclose))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; SETQ-AST

(defmethod compile-ast ((ast cleavir-ast:setq-ast) inserter)
  (let ((var (find-or-create-variable (cleavir-ast:lhs-ast ast)
                                      (function inserter)))
        (rv (compile-ast (cleavir-ast:value-ast ast) inserter)))
    (adjoin-variable inserter var)
    (cond ((eq rv :no-return) rv)
          (t
           (insert inserter
                   (make-instance 'cleavir-bir:writevar
                     :inputs (adapt inserter rv '(:object))
                     :outputs (list var)))
           ;; return no values
           ()))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; THE-AST

(defmethod compile-ast ((ast cleavir-ast:the-ast) inserter)
  (compile-ast (cleavir-ast:form-ast ast) inserter))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; DYNAMIC-ALLOCATION-AST

(defmethod compile-ast ((ast cleavir-ast:dynamic-allocation-ast) inserter)
  (compile-ast (cleavir-ast:form-ast ast) inserter))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; TODO
;;; CONSTANT-SYMBOL-VALUE-AST
;;; SET-CONSTANT-SYMBOL-VALUE-AST
;;; CONSTANT-FDEFINITION-AST

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; TYPEQ-AST

(defmethod compile-test-ast ((ast cleavir-ast:typeq-ast) inserter)
  (let ((rv (compile-ast (cleavir-ast:form-ast ast) inserter)))
    (when (eq rv :no-return) (return-from compile-test-ast rv))
    (let* ((obj (adapt inserter rv '(:object)))
           (tblock (make-iblock inserter)) (eblock (make-iblock inserter))
           (tq (make-instance 'cleavir-bir:typeq
                 :inputs obj :next (list tblock eblock)
                 :type-specifier (cleavir-ast:type-specifier ast))))
      (terminate inserter tq)
      (list tblock eblock))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; TYPEW-AST

(defmethod compile-test-ast ((ast cleavir-ast:typew-ast) inserter)
  (let ((rv (compile-ast (cleavir-ast:form-ast ast) inserter)))
    (when (eq rv :no-return) (return-from compile-test-ast rv))
    (let ((old-iblock (iblock inserter))
          (tblock (make-iblock inserter))
          (eblock (make-iblock inserter))
          (test-iblock (make-iblock inserter)))
      (begin inserter test-iblock)
      (let ((testrv (compile-test-ast (cleavir-ast:test-ast ast) inserter)))
        (proceed inserter old-iblock)
        (cond ((eq testrv :no-return)
               (terminate inserter (make-instance 'cleavir-bir:jump
                                     :inputs () :outputs () :unwindp nil
                                     :next (list test-iblock)))
               (return-from compile-test-ast testrv))
              (t
               (terminate inserter (make-instance 'cleavir-bir:typew
                                     :inputs (adapt inserter rv '(:object))
                                     :ctype (cleavir-ast:ctype ast)
                                     :next (list tblock eblock test-iblock)))))
        (destructuring-bind (realtblock realeblock) testrv
          (proceed inserter realtblock)
          (terminate inserter (make-instance 'cleavir-bir:choke
                                :next (list tblock)))
          (proceed inserter realeblock)
          (terminate inserter (make-instance 'cleavir-bir:choke
                                :next (list eblock)))))
      (list tblock eblock))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; THE-TYPEW-AST

(defmethod compile-ast ((ast cleavir-ast:the-typew-ast) inserter)
  (let ((rv (compile-ast (cleavir-ast:form-ast ast) inserter)))
    (when (eq rv :no-return) (return-from compile-ast rv))
    (let ((then-iblock (make-iblock inserter))
          (else-iblock (make-iblock inserter)))
      (terminate inserter (make-instance 'cleavir-bir:typew
                            :inputs (adapt inserter rv '(:object))
                            :ctype (cleavir-ast:ctype ast)
                            :next (list then-iblock else-iblock then-iblock)))
      (begin inserter else-iblock)
      (compile-ast (cleavir-ast:else-ast ast) inserter)
      (begin inserter then-iblock)))
  ;; if the value of the-typew is used, we'd have to introduce a variable,
  ;; since the form's value is used twice (as an input to typew, and as the
  ;; result of the-typew). But this is unlikely with the basic usage of using
  ;; the-typew in concert with multiple-value-extract. So we punt and return
  ;; no values.
  ())

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; UNREACHABLE-AST

(defmethod compile-ast ((ast cleavir-ast:unreachable-ast) inserter)
  (terminate inserter (make-instance 'cleavir-bir:unreachable))
  :no-return)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; LEXICAL-AST

(defmethod compile-ast ((ast cleavir-ast:lexical-ast) inserter)
  (let ((var (find-or-create-variable ast (function inserter))))
    (adjoin-variable inserter var)
    (list (insert inserter
                  (make-instance 'cleavir-bir:readvar :inputs (list var))))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; EQ-AST

(defmethod compile-test-ast ((ast cleavir-ast:eq-ast) inserter)
  (let ((args (compile-arguments
               (list (cleavir-ast:arg1-ast ast)
                     (cleavir-ast:arg2-ast ast))
               inserter)))
    (when (eq args :no-return) (return-from compile-test-ast args))
    (let ((tblock (make-iblock inserter)) (eblock (make-iblock inserter)))
      (terminate inserter (make-instance 'cleavir-bir:eqi
                            :inputs args :next (list tblock eblock)))
      (list tblock eblock))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; NEQ-AST

(defmethod compile-test-ast ((ast cleavir-ast:neq-ast) inserter)
  (let ((args (compile-arguments
               (list (cleavir-ast:arg1-ast ast)
                     (cleavir-ast:arg2-ast ast))
               inserter)))
    (when (eq args :no-return) (return-from compile-test-ast args))
    (let ((tblock (make-iblock inserter)) (eblock (make-iblock inserter)))
      (terminate inserter (make-instance 'cleavir-bir:eqi
                            :inputs args :next (list eblock tblock)))
      (list tblock eblock))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; CASE-AST

(defmethod compile-test-ast ((ast cleavir-ast:case-ast) inserter)
  (let ((rv (compile-ast (cleavir-ast:arg-ast ast) inserter))
        (comparees (cleavir-ast:comparees ast)))
    (when (eq rv :no-return) (return-from compile-test-ast rv))
    (let ((iblocks (loop repeat (1+ (length comparees))
                         collect (make-iblock inserter))))
      (terminate inserter (make-instance 'cleavir-bir:case
                            :inputs (adapt inserter rv '(:object))
                            :comparees comparees :next iblocks))
      iblocks)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; LOAD-TIME-VALUE-AST. Needs work.

(defmethod compile-ast ((ast cleavir-ast:load-time-value-ast) inserter)
  (declare (ignore inserter))
  (list
   (make-instance 'cleavir-bir:load-time-value
     :form (cleavir-ast:form ast) :read-only-p (cleavir-ast:read-only-p ast))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; IMMEDIATE-AST. Needs work.

(defmethod compile-ast ((ast cleavir-ast:immediate-ast) inserter)
  (declare (ignore inserter))
  (list
   (make-instance 'cleavir-bir:immediate :value (cleavir-ast:value ast))))
