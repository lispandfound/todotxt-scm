;; Main CLI interface
(declare (uses todotxt todotxt-utils))
(require-extension fmt fmt-unicode comparse irregex fmt-color numbers)
(use fmt fmt-color fmt-unicode irregex utils comparse numbers)

(define (colour-days-out date-str)
  (let [(days-from-now (date-cmp-now date-str))]
    (cond
     [(>= days-from-now 0) fmt-red]
     [(< days-from-now -2) fmt-blue]
     [#t fmt-white])))
(define (open file)
  (system (string-append "xdg-open" " " file)))
(define (as-ids arg)
  (map string->number (string-split arg ",")))
(define (join-structs structs accessing-function joiner)
  (string-join (map ->string (filter identity (map accessing-function structs))) joiner))
(define (colour-priority task)
  (let ((priority (task-priority task)))
    (cond
     ((equal? priority #\A) (fmt #f (fmt-bold priority)))
     (#t priority))))
(define (edit file)
  (let [(editor (or (get-environment-variable "EDITOR") "vi"))]
    (system (string-append editor " " file))))
(define (print-tasks tasks)
(fmt #t (fmt-unicode
                   (tabular
                    "| " (dsp (string-concatenate (list "ID\n" (join-structs tasks (lambda (x) (if (task-done x)
                                                                                                   "x"
                                                                                                   (fmt #f (num (task-id x))))) "\n")))) " | "
                    (dsp (string-concatenate (list "Priority\n" (join-structs tasks colour-priority "\n")))) " | "
                    (dsp (string-concatenate (list "Task\n" (join-structs tasks (lambda (task)
                                                                                  (if (task-done task)
                                                                                      (fmt #f (fmt-unicode (fmt-green (dsp (task-text task)))))
                                                                                      (task-text task))) "\n")))) " | "

                    (dsp (string-concatenate (list "Projects\n" (join-structs tasks (lambda (x) (string-join (task-project x) ", ")) "\n")))) " | "
                    (dsp (string-concatenate (list "Contexts\n" (join-structs tasks (lambda (x) (string-join (task-context x) ", ")) "\n")))) " | "
                    (dsp (string-concatenate (list "Addons\n" (join-structs tasks (lambda (x)
                                                                                    (string-join (map (lambda (addon)
                                                                                                        (fmt #f
                                                                                                             ((if (and (equal? (car addon) "due") (date-soon (cdr addon)))
                                                                                                                  (o dsp fmt-bold (colour-days-out (cdr addon)))
                                                                                                                  dsp) (car addon)) (dsp ":") (dsp (cdr addon)))) (task-property x)) ", "))
                                                                            "\n")))) " |"))))
(define-syntax define-cli-interface
  (syntax-rules ()
    ((_ args (actions* ...) (extension* ...))
     (define-cli-interface args (actions* ... extension* ...)))
    ((_ args (((argument-strings* ...) (argument-names* ...) . body)  actions* ...))
     (if (and (>= (length args) 1) (or (equal? (car args) '(argument-strings* ...)) (member (car args) '(argument-strings* ...))))
         (cond
          [(>= (length (cdr args)) (length '(argument-names* ...))) (begin . body)]
          [#t (format #t "Usage: todo ~a ~a~%"
                      (string-join '(argument-strings* ...) "/")
                      (string-join
                       (map (cut format #f "[~a]" <>) '(argument-names* ...)) " "))])
         (define-cli-interface args (actions* ...))))


    ((_ args ())
     (format #t "Usage: todo [action-name] [action-args]~%"))))
(define (with-task-at-id tasks id thunk)
  (map (lambda (task) (if (= (task-id task) id)
                          (thunk task)
                          task)) tasks))
(define (with-tasks-at-ids tasks ids thunk)
  (foldr (lambda (id tasks) (with-task-at-id tasks id thunk)) tasks ids))
(define (standard-task-filter filter-args show-all?)
  (lambda (x)
    (and (not (task-inbox x))
         (or show-all? (not (task-done x)) )
         (if (zero? (string-length filter-args))
             (not (task-inbox x))
             (irregex-match  (irregex (string-concatenate (list ".*" (irregex-quote filter-args) ".*"))) (task->string x))))))
(define (get-applicable-todo-directory . fallback-dirs)
  (let [(directories (cons "./" fallback-dirs))]
    (find (o file-exists? (cut string-append <> "todo.txt")) directories)))
(define (run args)
  (let* ((action (or (= (length args) 0) (car args)))
         (todo-dir (get-applicable-todo-directory (get-environment-variable "TODO_DIR")))
         (todo-file (string-append todo-dir "todo.txt"))
         (tasks (parse-filename todo-file))
         (done-file (string-append todo-dir "done.txt"))
         (done-tasks (parse-filename done-file))
         (report (string-append todo-dir "report.txt"))
         (action-args (cdr args)))
    (define-cli-interface args
      ((("list" "ls" "listall") ()
        (let ((task-count (+ (length tasks) (if (equal? action "listall")
                                                (length done-tasks)
                                                0)))
              (tasks (sort (filter (standard-task-filter (string-join action-args " ") (equal? action "listall"))
                                   (append tasks done-tasks)) task-priority<?)))
          (print-tasks tasks)
          (fmt #t
           "---" nl
           (length tasks) " out of " task-count " task" (if (= task-count 1)
                                                            ""
                                                            "s") " shown." nl)))
       (("next") ()
        (let [(tasks (sort (filter (standard-task-filter (string-join action-args " " ) #f) tasks) task-priority<?))]
          (if tasks
              (print (task->string (car tasks)))
              (print "No tasks to do next."))))
       (("edit") ()
        (edit (string-append editor " " todo-file)))
       (("inbox" "in") ()
        (let [(tasks (filter task-inbox tasks))]
          (print-tasks tasks)))
       (("refile") (id)
        (overwrite-file todo-file (format-tasks-as-file (with-task-at-id tasks (string->number (car action-args))
                                                                         (cut update-task <> inbox: #f)))))
       (("listproj" "lsprj") (project)
        (let ((project (car action-args)))
          (fmt #t (fmt-unicode (dsp (string-join (filter
                                                  (lambda (x) (if (= (length action-args) 0)
                                                                  #t
                                                                  (irregex-match  (irregex (string-concatenate (list ".*" (irregex-quote project) ".*"))) x)))
                                                  (delete-duplicates (flatten (map task-project tasks)))) "\n")) nl))))

       (("listcon" "lsc") (context)
        (let ((context (car action-args)))
          (fmt #t (fmt-unicode (dsp (string-join (filter
                                                  (lambda (x) (if (= (length action-args) 0)
                                                                  #t
                                                                  (irregex-match  (irregex (string-concatenate (list ".*" (irregex-quote context) ".*"))) x)))
                                                  (delete-duplicates (flatten (map task-context tasks)))) "\n")) nl))))

       (("rm" "del") (ids)
        (let ((ids (as-ids (car action-args))))
          (overwrite-file todo-file (format-tasks-as-file
                                     (remove (lambda (task)
                                               (member (task-id task) ids)) tasks)))))
       (("replace") (id todo)
        (let ((id (car action-args))
              (todo (cdr action-args)))
          (overwrite-file todo-file (fmt #f
                                         (dsp
                                          (format-tasks-as-file
                                           (remove (lambda (task)
                                                     (= (task-id task) (string->number id))) tasks)))
                                         (string-join todo " ")
                                         nl))))
       (("addon-modify" "admod" "am") (id key value)
        (let ((id (car action-args))
              (key (cadr action-args))
              (value (caddr action-args)))
          (overwrite-file todo-file (format-tasks-as-file (with-task-at-id tasks (string->number id)
                                                                           (lambda (t)
                                                                             (update-task t
                                                                                          property: (cons (cons key value) (rm-prop key (task-property t))))))))))
       (("addon-remove" "adrm" "ar") (id key)
        (let ((id (car action-args))
              (key (cadr action-args)))
          (overwrite-file todo-file (format-tasks-as-file (with-task-at-id tasks (string->number id)
                                                                           (lambda (t)
                                                                             (update-task t
                                                                                          property: (rm-prop key (task-property t)))))))))
       (("add" "a") ()
        (write-to-a-file todo-file (string-join action-args " ")))
       (("open" "o") (id)
        (let* [(id (string->number (car action-args)))
               (selected-task (find (lambda (t) (equal? id (task-id t))) tasks))
               (attachments (string-split (assoc-v "attach" (task-property selected-task)) ","))]
          (cond
           [(null-list? attachments) (fmt #t "No attachments found for the selected task." nl)]
           [(= (length attachments) 1) (edit (car attachments))]
           [#t (let [(attachment-pair (zip (map (cut + 1 <>) (iota (length attachments))) attachments))]
                 (fmt #t (fmt-join (lambda (attachment)
                                     (dsp (string-append (->string (car attachment)) ". " (cadr attachment)))) attachment-pair "\n")
                      nl
                      "Select attachment [1-" (length attachments) "]: ")
                 (let [(in (string->number (read-line)))]
                   (open (cadr (find (lambda (attachment) (equal? (car attachment) in)) attachment-pair)))))])))
       (("done" "do" "mark" "complete" "tick") (ids)
        (let ((ids (as-ids (car action-args))))
          (write-to-a-file done-file (format-tasks-as-file
                                      (remove (lambda (task)
                                                (not (task-done task)))
                                              (with-tasks-at-ids tasks ids (cut update-task <> done: #t)))))
          (overwrite-file todo-file (format-tasks-as-file (with-tasks-at-ids (remove (lambda (task)
                                                                                       (and (member (task-id task) ids)
                                                                                            (not (assoc "recur" (task-property task))))) tasks) ids
                                                                                            (lambda (t)
                                                                                              (if (and (assoc "recur" (task-property t)) (assoc "due" (task-property t)))
                                                                                                  (begin
                                                                                                    (fmt #t (fmt-unicode (fmt-bold "Task is recurrent, adding another in the future") nl) )
                                                                                                    (task-due-add t (string->number (assoc-v "recur" (task-property t)))))
                                                                                                  t)))))))
       (("bump" "promote") (ids)
        (let ((ids (as-ids (car action-args))))
          (overwrite-file todo-file (format-tasks-as-file (with-tasks-at-ids tasks ids
                                                                           (lambda (t)
                                                                             (update-task t priority: (cond ((equal? (task-priority t) #\A) #\A)
                                                                                                            ((not (task-priority t)) #\A)

                                                                                                            (#t (integer->char (- (char->integer (task-priority t)) 1)))))) )))))

       (("curb" "demote") (ids)
        (let ((ids (as-ids (car action-args))))
          (overwrite-file todo-file (format-tasks-as-file (with-tasks-at-ids tasks ids
                                                                           (lambda (t)
                                                                             (update-task t priority: (cond ((equal? (task-priority t) #\Z) #\Z)
                                                                                                            ((not (task-priority t)) #\Z)
                                                                                                            (#t (integer->char (+ (char->integer (task-priority t)) 1)))))))))))
       (("add-context" "ac") (ids context)
        (let ((ids (as-ids (car action-args)))
              (context (cadr action-args)))
          (overwrite-file todo-file (format-tasks-as-file (with-tasks-at-ids tasks ids
                                                                           (lambda (t)
                                                                             (update-task t context: (cons context (task-context t)))))))))
       (("rm-context" "rc") (ids context)
        (let ((ids (as-ids (car action-args)))
              (context (cadr action-args)))
          (overwrite-file todo-file (format-tasks-as-file (with-tasks-at-ids tasks ids
                                                                             (lambda (t)
                                                                               (update-task t context: (remove (cut equal? context <>) (task-context t)))))))))

       (("add-project" "ap") (ids project)
        (let ((ids (as-ids (car action-args)))
              (project (cadr action-args)))
          (overwrite-file todo-file (format-tasks-as-file (with-tasks-at-ids tasks ids
                                                                           (lambda (t)
                                                                             (update-task t project: (cons project (task-project t)))))))))
       (("rm-project" "rp") (ids project)
        (let ((ids (as-ids (car action-args)))
              (project (cadr action-args)))
          (overwrite-file todo-file (format-tasks-as-file (with-tasks-at-ids tasks ids
                                                                             (lambda (t)
                                                                               (update-task t project: (remove (cut equal? project <>) (task-project t)))))))))
       (("log") ()
        (write-to-a-file done-file (string-append "x " (string-join action-args " "))))
       (("pri") (id new-priority)
        (let ((id (car action-args))
              (new-priority (cadr action-args)))
              (if (or (equal? new-priority "-") (irregex-match "[A-Z]" (format #f "~a" new-priority)))
                  (overwrite-file todo-file (format-tasks-as-file (with-task-at-id tasks (string->number id)
                                                                                   (cut update-task <> priority: (if (equal? (caddr args) "-")
                                                                                                                     #f
                                                                                                                     new-priority)))))
                  (fmt #t (fmt-bold (fmt-red (dsp "Invalid Priority: "))) (dsp new-priority) nl))))))))
(if (> (length (argv)) 1)
    (run (cdr (argv)))
    (fmt #t (dsp "todo [action-name] [action-args]") nl))
