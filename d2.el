;;; d2.el --- Major mode for the D2 diagram language -*- lexical-binding: t; -*-

;; Copyright © 2026 Andreas Politz
;;
;; Author: Andreas Politz <mail@andreas-politz.de>
;; URL: http://github.com/politza/d2
;; Keywords: languages
;; Version: 0.0.1
;; Package-Requires: ((emacs "29.1"))

;; This file is not part of GNU Emacs.

;;; Commentary:

;; Treesitter-based major mode for editing d2 diagram definitions.

;;; License:

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:

(require 'treesit)
(require 'seq)

(defgroup d2 nil
  "Major mode for editing d2 diagram definitions."
  :prefix "d2-"
  :group 'languages
  :link '(url-link :tag "GitHub" "https://github.com/politza/d2")
  :link '(emacs-commentary-link :tag "Commentary" "d2"))

(defcustom d2-indent-offset 2
  "Number of indentiation spaces."
  :type 'natnum
  :safe 'natnump)

(defcustom d2-image-formats '((preview . png)
                              (convert . svg))
  "The default image formats used during various commands."
  :type 'alist
  :safe t)

(defcustom d2-preview-debounce 0.25
  "The delay in seconds before updating the preview image."
  :type 'natnum
  :safe 'natnump)

(defcustom d2-executable "d2"
  "The name or filename of the d2 executable."
  :type 'file
  :safe 'stringp)

(defun d2-executable ()
  (let ((executable (and d2-executable (executable-find d2-executable))))
    (unless (file-executable-p executable)
      (user-error "D2 executable not defined or not found: %s"
                  d2-executable))
    executable))

(defun d2-image-format (feature &optional override)
  (let ((format (or override
                    (alist-get feature d2-image-formats 'png))))
    (pcase format
      ((or 'png 'svg) format)
      (_ (user-error "Image format should be one of `svg' or `png': %s" format)))))

;;;; Major Mode

(defconst d2-grammar-recipe
  '(d2 "https://github.com/ravsii/tree-sitter-d2" "v0.7.2")
  "Tree-sitter grammar recipe for the d2 language.
The value is suitable for the `treesit-language-source-alist'.")

(defun d2-install-grammar ()
  "Install d2 language grammar, if not already available."
  (interactive)
  (unless (treesit-language-available-p 'd2)
    (message "Installing d2 tree-sitter grammar...")
    (let ((treesit-language-source-alist (list d2-grammar-recipe)))
      (treesit-install-language-grammar (car d2-grammar-recipe)))))

(defvar d2-mode-syntax-table
  (let ((table (make-syntax-table)))
    table)
  "Syntax table for d2 mode buffers.")

(defconst d2-mode-font-lock-queries
  `(([(comment) (block_comment)] @font-lock-comment-face)

    ([(label) (label_codeblock) (label_array)] @font-lock-string-face)

    (((label) @font-lock-keyword-face)
     (:match ,(regexp-opt '("null" "Null" "NULL")) @font-lock-keyword-face))

    (((label) @font-lock-constant-face)
     (:match ,(regexp-opt
               '("suspend"
                 "unsuspend"
                 "top-left"
                 "top-center"
                 "top-right"
                 "center-left"
                 "center-right"
                 "bottom-left"
                 "bottom-center"
                 "bottom-right"
                 "outside-top-left"
                 "outside-top-center"
                 "outside-top-right"
                 "outside-left-center"
                 "outside-right-center"
                 "outside-bottom-left"
                 "outside-bottom-center"
                 "outside-bottom-right"))
             @font-lock-constant-face))

    (((label_array) @font-lock-constant-face) 
     (:match
      ,(regexp-opt '("primary_key"
                     "PK"
                     "foreign_key"
                     "FK"
                     "unique"
                     "UNQ"
                     "NULL"
                     "NOT NULL"))
      @font-lock-constant-face))

    ((escape) @font-lock-escape-face)

    ((identifier) @font-lock-function-name-face)
    (((identifier) @font-lock-builtin-face)
     (:match ,(regexp-opt
               '("3d"
                 "animated"
                 "bold"
                 "border-radius"
                 "class"
                 "classes"
                 "constraint"
                 "d2-config"
                 "d2-legend"
                 "direction"
                 "double-border"
                 "fill"
                 "fill-pattern"
                 "filled"
                 "font"
                 "font-color"
                 "font-size"
                 "height"
                 "italic"
                 "label"
                 "layers"
                 "level"
                 "link"
                 "multiple"
                 "near"
                 "opacity"
                 "scenarios"
                 "shadow"
                 "shape"
                 "source-arrowhead"
                 "steps"
                 "stroke"
                 "stroke-dash"
                 "stroke-width"
                 "style"
                 "target-arrowhead"
                 "text-transform"
                 "tooltip"
                 "underline"
                 "vars"
                 "width"))
             @font-lock-builtin-face))
    
    (((identifier) @font-lock-keyword-face)
     (:match "_" @font-lock-keyword-face))
    
    (["$" "...$" "@" "...@"] @font-lock-keyword-face)
    
    ([(glob_filter) (inverse_glob_filter) (visibility_mark)]
     @font-lock-keyword-face)

    ((import) @font-lock-constant-face)

    ([(variable) (spread_variable)] @font-lock-variable-name-face)
    (variable (identifier) @font-lock-property-name-face)
    (spread_variable (identifier) @font-lock-property-name-face)
    (spread_variable
     (identifier_chain (identifier) @font-lock-property-name-face))

    ([
      (glob)
      (recursive_glob)
      (global_glob)
      ]
     @font-lock-string-face)

    (identifier (glob) @font-lock-string-face)

    ((connection) @font-lock-operator-face)
    ((connection_identifier) @font-lock-property-name-face)
    ((integer) @font-lock-number-face)
    ((float) @font-lock-number-face)
    ((boolean) @font-lock-constant-face)

    ((argument_name) @font-lock-variable-name-face)
    ((argument_type) @font-lock-type-face))
  "Font-lock queries for the d2 language.

See https://github.com/ravsii/tree-sitter-d2/blob/main/queries/highlights.scm")

(defconst d2-indent-rules 
  `((d2
     ((parent-is "source_file") column-0 0)
     ((node-is "}") parent-bol 0)
     ((parent-is "block") parent-bol d2-indent-offset)
     ((parent-is "comment") prev-adaptive-prefix 0)))
  "Tree-sitter indentation rules for d2.

The value is suitable for `treesit-simple-indent-rules'.")

(defconst d2-syntax-propertize-query
  '((label_codeblock _ @start (_) (_) _ @end)))

(defun d2-syntax-propertize-function (start end)
  "Propertize string delimiters between START and END."
  (let ((syntax (string-to-syntax "|")))
    (dolist (capture (treesit-query-capture
                      'd2 d2-syntax-propertize-query start end))
      (cond
       ((eq 'start (car capture))
        (put-text-property (treesit-node-start (cdr capture))
                           (1+ (treesit-node-start (cdr capture)))
                           'syntax-table syntax))
       (t
        (put-text-property (1- (treesit-node-end (cdr capture)))
                           (treesit-node-end (cdr capture))
                           'syntax-table syntax))))))

;;;###autoload
(define-derived-mode d2-mode prog-mode "D2"
  "Major mode for D2 diagram files."
  :syntax-table d2-mode-syntax-table

  (d2-install-grammar)
  (when (treesit-ready-p 'd2)
    (setq-local treesit-font-lock-feature-list '((all)))
    (treesit-parser-create 'd2)
    (setq-local treesit-font-lock-settings
                (treesit-font-lock-rules
                 :language 'd2
                 :feature 'all
                 :override t
                 d2-mode-font-lock-queries))
    (setq-local treesit-simple-indent-rules d2-indent-rules)
    (setq-local syntax-propertize-function
                #'d2-syntax-propertize-function)
    (treesit-major-mode-setup)))

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.d2\\'" . d2-mode))

;;;; Preview Mode

(require 'eieio)
(require 'image-mode)

(defconst d2--preview-state-property 'd2-preview-state)
(defconst d2--preview-parse-position-property 'd2-preview-mark)

(defclass d2--preview-state-class ()
  ((process :initarg :process)
   (source-buffer :initform (current-buffer))
   (input-filename :initarg :input-filename)
   (output-filename :initarg :output-filename)
   (preview-timer :initarg :preview-timer)
   (preview-buffer :initarg :preview-buffer)
   (preview-url :initform nil)))

(defvar-local d2--preview-state nil "Preview-state in a buffer.")

(defmacro d2--with-preview-state (state &rest body)
  (declare (indent 1) (debug (form body)))
  `(with-slots (process input-filename output-filename preview-timer preview-buffer preview-url)
       ,state
     ,@body))

(defun d2--preview-delete ()
  (when d2--preview-state
    (d2--with-preview-state d2--preview-state
      (when (process-live-p process)
        (delete-process process))
      (when (and (processp process)
                 (process-buffer process)
                 (buffer-live-p (process-buffer process)))
        (kill-buffer (process-buffer process)))
      (when input-filename
        (delete-file input-filename))
      (when output-filename
        (delete-file output-filename))
      (when (timerp preview-timer)
        (cancel-timer preview-timer))
      (when (and preview-buffer
                 (buffer-live-p (get-buffer preview-buffer)))
        (kill-buffer preview-buffer)))
    (setq d2--preview-state nil)))

(defun d2--preview-live-p ()
  (and d2--preview-state
       (process-live-p (oref d2--preview-state process))))

(defun d2--preview-setup ()
  "Initializes the preview process if required."
  (unless (d2--preview-live-p)
    (let ((format (d2-image-format 'preview))
          (executable (d2-executable))
          (input-filename nil)
          (output-filename nil)
          (preview-buffer nil)
          (process nil))
      (condition-case error
          (progn
            (d2--preview-delete)
            (setq input-filename (make-temp-file "d2-preview-input-" nil ".d2"))
            (setq output-filename (make-temp-file "d2-preview-output-" nil (format ".%s" format)))
            (setq preview-buffer (generate-new-buffer-name (format "*d2-preview %s*" (buffer-name))))
            (setq process (make-process
                           :name "d2-preview"
                           :buffer (generate-new-buffer "*d2-preview-process*")
                           :noquery t
                           :filter #'d2--preview-process-filter
                           :command (list
                                     executable
                                     "--watch"
                                     "--browser" "0"
                                     input-filename
                                     output-filename)))
            (setq d2--preview-state
                  (make-instance
                   'd2--preview-state-class
                   :input-filename input-filename
                   :output-filename output-filename
                   :preview-buffer preview-buffer
                   :preview-timer nil
                   :process process))
            (process-put process d2--preview-state-property d2--preview-state))
        (error
         (when input-filename
           (delete-file input-filename))
         (when output-filename
           (delete-file output-filename))
         (when (buffer-live-p preview-buffer)
           (kill-buffer preview-buffer))
         (when process
           (delete-process process))
         (signal (car error) (cdr error)))))))

(defun d2--preview-process-filter (process input)
  (when (buffer-live-p (process-buffer process))
    (with-current-buffer (process-buffer process)
      (let* ((position (point))
             (parse-position (or (process-get process d2--preview-parse-position-property)
                                 1))
             (moving (= position (process-mark process)))
             (state (process-get process d2--preview-state-property)))
        (save-excursion
          (goto-char (process-mark process))
          (insert input)
          (set-marker (process-mark process) (point)))
        (when moving
          (goto-char (process-mark process)))
        (save-excursion
          (goto-char parse-position)
          (while (/= (point-max)
                     (line-end-position))
            (let ((line (buffer-substring-no-properties (point) (line-end-position))))
              (d2--preview-process-parse-line state line)
              (forward-line)
              (process-put process d2--preview-parse-position-property (point)))))))))

(defun d2--preview-process-parse-line (state line)
  (cond
   ((string-match "^success: listening on \\(.*\\)" line)
    (oset state preview-url (match-string 1 line)))
   ((string-match-p "^success: successfully compiled " line)
    (d2--preview-update-buffer state))
   ((string-prefix-p "error:" line)
    (message "d2 process: %s" line))))

(defun d2--preview-update-buffer (state)
  (when (display-graphic-p)
    (d2--with-preview-state state
      (unless (buffer-live-p preview-buffer)
        (get-buffer-create preview-buffer))
      (with-current-buffer preview-buffer
        (let ((inhibit-read-only t))
          (erase-buffer))
        (when (file-exists-p output-filename)
          (insert-file-contents-literally output-filename))
        (unless (derived-mode-p 'image-mode)
          (image-mode))
        (image-after-revert-hook)))))

(defun d2--preview-update-diagram (buffer)
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when d2--preview-state
        (d2--with-preview-state d2--preview-state
          (write-region nil nil input-filename nil 'silent))))))

(defun d2--after-change-function (&rest _)
  (when d2--preview-state
    (d2--with-preview-state d2--preview-state
      (when (timerp preview-timer)
        (cancel-timer preview-timer))
      (setf preview-timer
            (run-with-idle-timer
             d2-preview-debounce nil
             #'d2--preview-update-diagram
             (current-buffer))))))

;;;###autoload
(define-minor-mode d2-preview-mode
  "Preview D2 diagrams using the d2 command."
  :ligther nil
  (cond
   (d2-preview-mode
    (d2--preview-setup)
    (add-hook 'after-change-functions #'d2--after-change-function nil t)
    (add-hook 'kill-buffer-hook #'d2--preview-delete nil t)
    (if (display-graphic-p)
        (d2-preview-display)
      (message "Not displaying the preview because this frame is not able to display images")))
   (t
    (remove-hook 'after-change-functions #'d2--after-change-function t)
    (remove-hook 'kill-buffer-hook #'d2--preview-delete t)
    (d2--preview-delete))))

(defun d2-preview-display ()
  "Display the preview buffer."
  (interactive)
  (unless d2--preview-state
    (user-error "Buffer is not associated with a preview"))
  (d2--with-preview-state d2--preview-state
    (unless (buffer-live-p preview-buffer)
      (get-buffer-create preview-buffer))
    (d2--preview-update-diagram (current-buffer))
    (display-buffer preview-buffer)))

(defun d2-preview-url ()
  "Returns the preview URL of the current buffer."
  (unless d2--preview-state
    (error "Buffer is not associated with a preview"))
  (d2--with-preview-state d2--preview-state preview-url))

(defun d2-preview-browse (&optional interactive)
  "Browser the preview URL of the current buffer."
  (interactive (list t))
  (unless d2--preview-state
    (user-error "Buffer is not associated with a preview"))
  (let ((preview-url (d2-preview-url)))
    (or preview-url
        (user-error "No preview URL available to browse"))
    (browse-url preview-url)
    (when interactive
      (message "Opened %s in browser" preview-url))))

(provide 'd2)
;;; d2.el ends here
