(declare (unit todotxt))
(require-extension irregex)
(require-extension defstruct comparse srfi-19-date)
(use irregex comparse defstruct utils srfi-14 srfi-19-date)
(defstruct task
  ;; (A) 2011-03-02 Call Mum +family @phone
  ;; x Do this really important thing
  id done completed-date date priority text project context property)
;; Todo.txt regexes
(define (new-task)
  (make-task
   projects: '()
   contexts: '()
   addons: '()))
(define (assoc-v k l)
  (let [(kv (assoc k l))]
    (if kv
        (cdr kv)
        '())))
(define (merge-alist l)
  (let loop [(acc '()) (l l)]
    (if (null-list? l)
        acc
        (let* [(h (car l))
               (k (car h))
               (v (cdr h))]
          (loop (cons (cons k (append (list v) (assoc-v k acc))) acc) (cdr l))))))
(define (merge-text l)
  (cons (cons 'text (string-trim-both (string-join (reverse (assoc-v 'text l)) " "))) l))
(define (weed l)
  (filter identity l))
(define space
  char-set:whitespace)
(define -space
  (char-set-difference char-set:graphic char-set:whitespace))
(define legal-text
  (as-string (repeated (in -space))))
(define digit
  (in char-set:digit))
(define (as-number c)
  (bind (as-string c)
        (lambda (x)
          (result (string->number x)))))
(define (digits n)
  (as-number (repeated digit n)))
(define dash
  (char-seq "-"))
(define (date k)
  (sequence* ((y (digits 4)) (_ dash) (m (digits 2)) (_ dash) (d (digits 2)))
             (result (cons k (make-date 0 0 0 0 d m y)))))
(define completed
  (bind (char-seq "x ")
        (lambda (x)
          (when x
            (result (cons 'done #t))))))
(define (mark-whitespace p)
  (bind p
        (lambda (x) (result (cons 'whitespace x)))))
(define whitespace
  (mark-whitespace (as-string (one-or-more (in space)))))
(define non-mandatory-whitespace
  (mark-whitespace (as-string (zero-or-more (in space)))))
(define done
  (sequence completed  (maybe (date 'completed-date))))
(define priority-char
  (char-seq-match "[A-Z]"))
(define priority
  (enclosed-by (is #\() (as-string priority-char) (char-seq ") ")))
(define (denoted-by k p)
  (bind (preceded-by p legal-text)
             (lambda (v) (result (cons k v))))
  )
(define context
  (denoted-by 'context (is #\@)))
(define project
  (denoted-by 'project (is #\+)))
(define property-text
  (as-string (repeated (in (char-set-difference char-set:graphic (->char-set " :"))))))
(define property
  (sequence* ((k property-text) (_ (char-seq ":")) (v legal-text))
             (result (cons 'property (cons k v)))))
(define text
  (bind (none-of* property context project legal-text)
        (lambda (x)
          (result (cons 'text x)))))
(define (assoc-or k l default)
  (if (and l (assoc k l))
      (assoc-v k l)
      default))
(define (assoc-or-f k l)
  (assoc-or k l #f))
(define generic-section
  (any-of property context project text))
(define todo
  (sequence* ((t generic-section) (_ non-mandatory-whitespace))
             (result t)))
(define task
  (sequence* ((d (maybe done)) (_ (maybe whitespace)) (p (maybe priority)) (start-date (maybe (sequence* ((d (date 'date)) (_ whitespace)) d))) (t* (repeated todo until: end-of-input)))
             (let [(t* (merge-text (merge-alist (weed t*))))
                   (d (if (not d) d (weed d)))]
               (result (update-task (new-task)
                            done: (assoc-or-f 'done d)
                            completed-date: (assoc-or-f 'completed d)
                            priority: p
                            date: start-date
                            text: (assoc-or-f 'text t*)
                            project: (assoc-or 'project t* '())
                            context: (assoc-or 'context t* '())
                            property: (assoc-or 'property t* '()))))))
(define (task-priority<? a b)
  (cond
   ((and (task-priority a) (task-priority b)) (string<=? (task-priority a) (task-priority b)))
   ((not (task-priority a)) #f)
   ((not (task-priority b)) #t)))
(define (task->string task)
  (string-join (filter identity
                       (flatten (list
                                 (if (task-done task)
                                     "x"
                                     #f)
                                 (if (task-priority task)
                                     (format "(~a)" (task-priority task))
                                     #f)
                                 (task-completed-date task)
                                 (task-date task)
                                 (task-text task)
                                 (map (lambda (x) (string-concatenate (list "+" x)))
                                      (sort (task-project task) string<?))
                                 (map (lambda (x) (string-concatenate (list "@" x)))
                                      (sort (task-context task) string<?))
                                 (map (lambda (x) (format #f "~a:~a" (car x) (cdr x))) (task-property task))))) " "))
(define (parse-filename file)
  (let loop ((lines (string-split (read-all file) "\n")) (acc '()) (id 1))
    (if (null? lines)
        (reverse acc)
        (loop (cdr lines) (cons (update-task (parse task (car lines))
                                             id: id) acc) (+ id 1)))))
(define (format-tasks-to-alists tasks)
  (map task->alist tasks))
(define (format-tasks-as-file tasks)
  (string-append (string-join (map task->string tasks) "\n") "\n"))
;; Todo list manipulation
