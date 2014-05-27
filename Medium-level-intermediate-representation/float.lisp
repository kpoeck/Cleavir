(in-package #:cleavir-mir)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction SHORT-FLOAT-UNBOX-INSTRUCTION.
;;;
;;; This instruction takes a single input, which must be a boxed
;;; SHORT-FLOAT.  It has a single output which is the corresponding
;;; unboxed SHORT-FLOAT value.
;;;
;;; This instruction can be used by implementations that support the
;;; SHORT-FLOAT data type.

(defclass short-float-unbox-instruction (instruction one-successors-mixin)
  ())

(defun make-short-float-unbox-instruction (input output successor)
  (make-instance 'short-float-unbox-instruction
    :inputs (list input)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction SHORT-FLOAT-BOX-INSTRUCTION.
;;;
;;; This instruction takes a single input, which must be an unboxed
;;; SHORT-FLOAT.  It has a single output which is the corresponding
;;; boxed SHORT-FLOAT value.
;;;
;;; This instruction can be used by implementations that support the
;;; SHORT-FLOAT data type.

(defclass short-float-box-instruction (instruction one-successors-mixin)
  ())

(defun make-short-float-box-instruction (input output successor)
  (make-instance 'short-float-box-instruction
    :inputs (list input)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction SINGLE-FLOAT-UNBOX-INSTRUCTION.
;;;
;;; This instruction takes a single input, which must be a boxed
;;; SINGLE-FLOAT.  It has a single output which is the corresponding
;;; unboxed SINGLE-FLOAT value.

(defclass single-float-unbox-instruction (instruction one-successors-mixin)
  ())

(defun make-single-float-unbox-instruction (input output successor)
  (make-instance 'single-float-unbox-instruction
    :inputs (list input)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction SINGLE-FLOAT-BOX-INSTRUCTION.
;;;
;;; This instruction takes a single input, which must be an unboxed
;;; SINGLE-FLOAT.  It has a single output which is the corresponding
;;; boxed SINGLE-FLOAT value.

(defclass single-float-box-instruction (instruction one-successors-mixin)
  ())

(defun make-single-float-box-instruction (input output successor)
  (make-instance 'single-float-box-instruction
    :inputs (list input)
    :outputs (list output)
    :successors (list successor)))
