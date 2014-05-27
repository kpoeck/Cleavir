(in-package #:cleavir-mir)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction CAR-INSTRUCTION.
;;;
;;; This instruction takes a single input which is assumed to be a
;;; CONS cell, and produces a single output, which is the contents of
;;; the CAR of the cons cell.

(defclass car-instruction (instruction one-successor-mixin)
  ())

(defun make-car-instruction (input output successor)
  (make-instance 'car-instruction
    :inputs (list input)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction CDR-INSTRUCTION.
;;;
;;; This instruction takes a single input which is assumed to be a
;;; CONS cell, and produces a single output, which is the contents of
;;; the CDR of the cons cell.

(defclass cdr-instruction (instruction one-successor-mixin)
  ())

(defun make-cdr-instruction (input output successor)
  (make-instance 'cdr-instruction
    :inputs (list input)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction RPLACA-INSTRUCTION
;;;
;;; This instruction takes two inputs.  The first input is assumed to
;;; be a CONS cell, and the second can be any object.  It has no
;;; outputs.  It replaces the CAR of the CONS cell with the object in
;;; the second input. 

(defclass rplaca-instruction (instruction one-successor-mixin)
  ())

(defun make-rplaca-instruction (input1 input2 successor)
  (make-instance 'rplaca-instruction
    :inputs (list input1 input2)
    :outputs '()
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction RPLACD-INSTRUCTION
;;;
;;; This instruction takes two inputs.  The first input is assumed to
;;; be a CONS cell, and the second can be any object.  It has no
;;; outputs.  It replaces the CDR of the CONS cell with the object in
;;; the second input. 

(defclass rplacd-instruction (instruction one-successor-mixin)
  ())

(defun make-rplacd-instruction (input1 input2 successor)
  (make-instance 'rplacd-instruction
    :inputs (list input1 input2)
    :outputs '()
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction SLOT-READ-INSTRUCTION.
;;;
;;; This instruction takes two inputs.  The first input is assumed
;;; to be a standard instance.  The second is assumed to be a FIXNUM
;;; and represents the index in the instance of the slot to be read.
;;; This instruction produces a single output, which is the contents
;;; of the SLOT.

(defclass slot-read-instruction (instruction one-successor-mixin)
  ())

(defun make-slot-read-instruction (input1 input2 output successor)
  (make-instance 'slot-read-instruction
    :inputs (list input1 input2)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction SLOT-WRITE-INSTRUCTION
;;;
;;; This instruction takes three inputs.  The first input is assumed
;;; to be a standard instance.  The second is assumed to be a FIXNUM
;;; and represents the index in the instance of the slot to be
;;; written.  The third is the value to write.  This instruction
;;; replaces the contents of the slot with the new value.

(defclass slot-write-instruction (instruction one-successor-mixin)
  ())

(defun make-slot-write-instruction (input1 input2 input3 successor)
  (make-instance 'slot-write-instruction
    :inputs (list input1 input2 input3)
    :outputs '()
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction AREF-INSTRUCTION.
;;;
;;; This instruction takes two inputs.  The first input is assumed
;;; to be a general array.  The second is assumed to be a FIXNUM
;;; and represents the index in the instance of the element to be read.
;;; This instruction produces a single output, the element read.

(defclass aref-instruction (instruction one-successor-mixin)
  ())

(defun make-aref-instruction (input1 input2 output successor)
  (make-instance 'aref-instruction
    :inputs (list input1 input2)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction SHORT-FLOAT-AREF-INSTRUCTION.
;;;
;;; This instruction takes two inputs.  The first input is assumed
;;; to be an array specialized to SHORT-FLOAT.  The second is assumed
;;; to be a FIXNUM and represents the index in the instance of the
;;; element to be read.  This instruction produces a single output,
;;; the element read, which is an unboxed SHORT-FLOAT.

(defclass short-float-aref-instruction (instruction one-successor-mixin)
  ())

(defun make-short-float-aref-instruction (input1 input2 output successor)
  (make-instance 'short-float-aref-instruction
    :inputs (list input1 input2)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction SINGLE-FLOAT-AREF-INSTRUCTION.
;;;
;;; This instruction takes two inputs.  The first input is assumed
;;; to be an array specialized to SINGLE-FLOAT.  The second is assumed
;;; to be a FIXNUM and represents the index in the instance of the
;;; element to be read.  This instruction produces a single output,
;;; the element read, which is an unboxed SINGLE-FLOAT.

(defclass single-float-aref-instruction (instruction one-successor-mixin)
  ())

(defun make-single-float-aref-instruction (input1 input2 output successor)
  (make-instance 'single-float-aref-instruction
    :inputs (list input1 input2)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction DOUBLE-FLOAT-AREF-INSTRUCTION.
;;;
;;; This instruction takes two inputs.  The first input is assumed
;;; to be an array specialized to DOUBLE-FLOAT.  The second is assumed
;;; to be a FIXNUM and represents the index in the instance of the
;;; element to be read.  This instruction produces a single output,
;;; the element read, which is an unboxed DOUBLE-FLOAT.

(defclass double-float-aref-instruction (instruction one-successor-mixin)
  ())

(defun make-double-float-aref-instruction (input1 input2 output successor)
  (make-instance 'double-float-aref-instruction
    :inputs (list input1 input2)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction LONG-FLOAT-AREF-INSTRUCTION.
;;;
;;; This instruction takes two inputs.  The first input is assumed
;;; to be an array specialized to LONG-FLOAT.  The second is assumed
;;; to be a FIXNUM and represents the index in the instance of the
;;; element to be read.  This instruction produces a single output,
;;; the element read, which is an unboxed LONG-FLOAT.

(defclass long-float-aref-instruction (instruction one-successor-mixin)
  ())

(defun make-long-float-aref-instruction (input1 input2 output successor)
  (make-instance 'long-float-aref-instruction
    :inputs (list input1 input2)
    :outputs (list output)
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction ASET-INSTRUCTION.
;;;
;;; This instruction takes three inputs.  The first input is assumed
;;; to be a general array.  The second is assumed to be a FIXNUM
;;; and represents the index in the instance of the element to be read.
;;; The third input is the element to be stored in the array.

(defclass aset-instruction (instruction one-successor-mixin)
  ())

(defun make-aset-instruction (input1 input2 input3 successor)
  (make-instance 'aset-instruction
    :inputs (list input1 input2 input3)
    :outputs ()
    :successors (list successor)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; Instruction SHORT-FLOAT-ASET-INSTRUCTION.
;;;
;;; This instruction takes three inputs.  The first input is assumed
;;; to be an array specialized to SHORT-FLOAT.  The second is assumed
;;; to be a FIXNUM and represents the index in the instance of the
;;; element to be read.  The third input is assumed to be an unboxed
;;; SHORT-FLOAT to be stored as an element in the array.

(defclass short-float-aset-instruction (instruction one-successor-mixin)
  ())

(defun make-short-float-aset-instruction (input1 input2 input3 successor)
  (make-instance 'short-float-aset-instruction
    :inputs (list input1 input2 input3)
    :outputs ()
    :successors (list successor)))
