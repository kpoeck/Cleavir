(cl:in-package #:common-lisp-user)

(defpackage #:cleavir-partial-inlining
  (:use #:common-lisp)
  (:export #:inline-one-instruction)
  (:export #:do-inlining)
  (:export #:interpolable-function-analyze)
  (:export #:interpolable-function-analyze-1))
