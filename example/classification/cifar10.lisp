;; -*- coding:utf-8; mode:lisp -*-

(in-package :cl-random-forest)

;;; load dataset =========================================================

;; Download CIFAR-10 binary version and extract to directory.
;; http://www.cs.toronto.edu/~kriz/cifar.html
(defparameter dir #P"/home/wiz/datasets/cifar-10-batches-bin/")

(defparameter dim 3072)
(defparameter n-class 10)

(defparameter x
  (make-array '(50000 3072) :element-type 'double-float))

(defparameter y
  (make-array 50000 :element-type 'fixnum))

(defparameter x.t
  (make-array '(10000 3072) :element-type 'double-float))

(defparameter y.t
  (make-array 10000 :element-type 'fixnum))

(defun load-cifar (file datamatrix target n)
  (with-open-file (s file :element-type '(unsigned-byte 8))
    (loop for i from (* n 10000) below (* (1+ n) 10000) do
      (setf (aref target i) (read-byte s))
      (loop for j from 0 below 3072 do
        (setf (aref datamatrix i j) (coerce (read-byte s) 'double-float))))
    'done))

(loop for i from 0 to 4 do
  (load-cifar (merge-pathnames (format nil "data_batch_~A.bin" (1+ i)) dir) x y i))

(load-cifar (merge-pathnames "test_batch.bin" dir) x.t y.t 0)

;;; ======================================================================

(defparameter dtree
  (make-dtree n-class x y :max-depth 15 :n-trial 28 :min-region-samples 5))

;; Prediction
(predict-dtree dtree x 0) ; => 6 (correct)

;; Testing with training data
(test-dtree dtree x y)
;; Accuracy: 55.022003%, Correct: 27511, Total: 50000

;; Testing with test data
(test-dtree dtree x.t y.t)
;; Accuracy: 26.07%, Correct: 2607, Total: 10000

;;; Make Random Forest ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;; Enable/Disable parallelizaion
(setf lparallel:*kernel* (lparallel:make-kernel 4))
;; (setf lparallel:*kernel* nil)

;; 6.079 seconds (1 core), 2.116 seconds (4 core)
(defparameter forest
  (make-forest n-class x y
               :n-tree 500 :bagging-ratio 0.1 :max-depth 10 :n-trial 32 :min-region-samples 5))

;; Prediction
(predict-forest forest x 0) ; => 6 (correct)

;; Testing with test data
(test-forest forest x.t y.t)
;; Accuracy: 38.2%, Correct: 3820, Total: 10000

;;; Global Refinement of Random Forest ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Generate sparse data from Random Forest

;; 2.625 seconds of real time (4 core)
(defparameter x.r (make-refine-dataset forest x))

;; 0.995 seconds (1 core), 0.322 seconds (4 core)
(defparameter x.r.t
  (make-refine-dataset forest x.t))

(defparameter refine-learner (make-refine-learner forest))

;; 4.347 seconds (1 core), 2.281 seconds (4 core), Accuracy: 98.259%
(train-refine-learner-process refine-learner x.r y x.r.t y.t)

(test-refine-learner refine-learner x.r.t y.t)
;; Accuracy: 48.32%, Correct: 4832, Total: 10000

;; 5.859 seconds (1 core), 4.090 seconds (4 core), Accuracy: 98.29%
(loop repeat 10 do
  (train-refine-learner refine-learner x.r y)
  (test-refine-learner refine-learner x.r.t y.t))

(test-refine-learner refine-learner x.r y)

;; Make a prediction
(predict-refine-learner forest refine-learner x 0) ; => 6

;;; Global Prunning of Random Forest ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(loop repeat 10 do
  (sb-ext:gc :full t)
  (room)
  (format t "~%Making refine-dataset~%")
  (setf x.r (make-refine-dataset forest x))
  (format t "Making refine-test~%")
  (setf x.r.t (make-refine-dataset forest x.t))
  (format t "Re-learning~%")
  (setf refine-learner (make-refine-learner forest))
  (train-refine-learner-process refine-learner x.r y x.r.t y.t)
  (test-refine-learner refine-learner x.r.t y.t)
  (format t "Pruning. leaf-size: ~A" (length (collect-leaf-parent forest)))
  (pruning! forest refine-learner 0.5)
  (format t " -> ~A ~%" (length (collect-leaf-parent forest))))
