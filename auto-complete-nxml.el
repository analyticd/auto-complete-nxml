;;; auto-complete-nxml.el --- do completion by auto-complete.el on nXML-mode

;; Copyright (C) 2013  Hiroaki Otsu

;; Author: Hiroaki Otsu <ootsuhiroaki@gmail.com>
;; Keywords: completion, html, xml
;; Version: 0.1

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; 
;; This extension provides completion by auto-complete.el on nXML-mode.

;;; Dependency:
;; 
;; - Following have been installed, auto-complete.el, auto-complete-config.el.
;; - nXML-mode is available.

;;; Installation:
;;
;; Put this to your load-path.
;; And put the following lines in your .emacs or site-start.el file.
;; 
;; (require 'auto-complete-nxml)

;;; Customization:
;; 
;; Nothing.

;;; API:
;; 
;; Nothing.
;; 
;; [Note] Functions and variables other than listed above, Those specifications may be changed without notice.

;;; Tested On:
;; 
;; - Emacs ... GNU Emacs 23.3.1 (i386-mingw-nt5.1.2600) of 2011-08-15 on GNUPACK
;; - auto-complete.el ... Version 1.4
;; - auto-complete-config.el ... Version 1.4


;; Enjoy!


(eval-when-compile (require 'cl))
(require 'rx)
(require 'regexp-opt)
(require 'nxml-util)
(require 'rng-nxml)
(require 'auto-complete)
(require 'auto-complete-config)

(defvar auto-complete-nxml-regexp-jump-current-tag-start (rx-to-string `(and (group (or "<" ">")) (+ (not (any ">"))))))
(defun auto-complete-nxml-point-inside-tag-p ()
  (save-excursion
    (and (re-search-backward auto-complete-nxml-regexp-jump-current-tag-start nil t)
         (string= (match-string-no-properties 1) "<"))))

(defvar auto-complete-nxml-regexp-point-inside-attr (rx-to-string `(and (+ space) (group (+ (not (any space)))) "=" (or "\"" "'")
                                                       (* (not (any "\"" "'"))) point)))
(defvar auto-complete-nxml-buffer-current-attr nil)
(make-variable-buffer-local 'auto-complete-nxml-buffer-current-attr)
(defun auto-complete-nxml-update-current-attr ()
  (let* ((attrnm ""))
    (when (auto-complete-nxml-point-inside-tag-p)
      (save-excursion
        (when (re-search-backward auto-complete-nxml-regexp-point-inside-attr nil t)
          (setq attrnm (match-string-no-properties 1)))))
    (setq auto-complete-nxml-buffer-current-attr attrnm)))

(defvar auto-complete-nxml-regexp-point-tagnm (rx-to-string `(and "<" (* (not (any "/" ">" space))) point)))
(defvar auto-complete-nxml-regexp-point-attrnm (rx-to-string `(and (or (and "<" (+ (any "a-zA-Z0-9:-")))
                                                           (and (not (any "=")) "\"")
                                                           (and (not (any "=")) "'"))
                                                       (+ space) (* (any "a-zA-Z0-9-")) point)))
(defvar auto-complete-nxml-regexp-point-cssprop (rx-to-string `(and (or "\"" "'" ";") (* space) (* (any "a-zA-Z0-9-")) point)))
(defvar auto-complete-nxml-regexp-point-cssprop-value (rx-to-string `(and (or "\"" "'" ";" space) (group (+ (any "a-zA-Z0-9-"))) ":" (* space)
                                                              (* (not (any ":" "\"" "'"))) point)))
(defun auto-complete-nxml-get-css-candidates ()
  (ignore-errors
    (save-excursion
      (when (and (not (re-search-backward auto-complete-nxml-regexp-point-tagnm nil t))
                 (auto-complete-nxml-point-inside-tag-p)
                 (auto-complete-nxml-update-current-attr)
                 (string= auto-complete-nxml-buffer-current-attr "style"))
        (cond ((re-search-backward auto-complete-nxml-regexp-point-cssprop nil t)
               (loop for prop in ac-css-property-alist
                     collect (car prop)))
              (t
               (ac-css-property-candidates)))))))

(defun auto-complete-nxml-get-tag-value-candidates ()
  (ignore-errors
    (save-excursion
      (when (not (auto-complete-nxml-point-inside-tag-p))
        (ac-update-word-index)
        (ac-word-candidates (lambda (buffer)
                              (derived-mode-p (buffer-local-value 'major-mode buffer))))))))

(defvar auto-complete-nxml-candidates nil)
(defun auto-complete-nxml-get-candidates ()
  (let* ((auto-complete-nxml-candidates))
    (flet ((rng-complete-before-point (start table prompt &optional predicate hist)
                                      (let* ((inputw (buffer-substring-no-properties start (point))))
                                        (setq auto-complete-nxml-candidates
                                              (cond ((functionp table)
                                                     (funcall table inputw nil t))
                                                    ((listp table)
                                                     (loop for e in table
                                                           collect (car e)))))
                                        nil)))
      (ignore-errors (rng-complete))
      auto-complete-nxml-candidates)))

(defun auto-complete-nxml-expand-tag ()
  (let* ((currpt (point))
         (tagnm (save-excursion
                  (skip-syntax-backward "w")
                  (buffer-substring-no-properties (point) currpt)))
         (qname))
    (cond ((rng-qname-p tagnm)
           (setq qname (rng-expand-qname tagnm t 'rng-start-tag-expand-recover))
           (when (and qname
                      (rng-match-start-tag-open qname)
                      (or (not (rng-match-start-tag-close))
                          (and (car qname)
                               (not rng-open-elements))))
             (insert " ")))
          ((member tagnm rng-complete-extra-strings)
           (insert ">")))))

(defvar auto-complete-nxml-regexp-point-expand-xmlns (rx-to-string `(and "xmlns="
                                                                         (group (or "\"" "'"))
                                                                         (group (+ (not (any "\"" "'"))))
                                                                         point)))
(defun auto-complete-nxml-expand-other-xmlns ()
  (when (save-excursion
          (re-search-backward auto-complete-nxml-regexp-point-expand-xmlns nil t))
    (insert (match-string-no-properties 1))
    (let* ((defns (concat ":" (match-string-no-properties 2))))
      (loop for nssym in (rng-match-possible-namespace-uris)
            for ns = (symbol-name nssym)
            for prefix = (when (not (string= ns defns))
                           (loop for f in rng-schema-locating-files
                                 for id = (loop for rule in (rng-get-parsed-schema-locating-file f)
                                                for nscons = (when (eq (car rule) 'namespace)
                                                               (assq 'ns (cdr rule)))
                                                for idcons = (when (and nscons
                                                                        (string= (concat ":" (cdr nscons)) ns))
                                                               (assq 'typeId (cdr rule)))
                                                if idcons return (cdr idcons)
                                                finally return nil)
                                 if id return (loop for rule in (rng-get-parsed-schema-locating-file f)
                                                    for idcons = (when (eq (car rule) 'documentElement)
                                                                   (assq 'typeId (cdr rule)))
                                                    for prefcons = (when (and idcons
                                                                              (string= (cdr idcons) id))
                                                                     (assq 'prefix (cdr rule)))
                                                    if prefcons return (cdr prefcons)
                                                    finally return nil)))
            if prefix
            do (progn (cond (indent-tabs-mode
                             (insert "\n")
                             (indent-for-tab-command))
                            (t
                             (insert " ")))
                      (insert (format "xmlns:%s=\"%s\"" prefix (substring ns 1))))))))


(defvar ac-source-nxml-tag
  '((candidates . auto-complete-nxml-get-candidates)
    (prefix . "<\\([a-zA-Z0-9:-]*\\)")
    (symbol . "t")
    (document . auto-complete-nxml-get-document-tag)
    (requires . 0)
    (cache)
    (limit . nil)
    (action . (lambda ()
                (auto-complete-nxml-expand-tag)))))

(defvar ac-source-nxml-attr
  '((candidates . auto-complete-nxml-get-candidates)
    (prefix . "\\(?:<[a-zA-Z0-9:-]+\\|[^=]\"\\|[^=]'\\)\\s-+\\([a-zA-Z0-9-]*\\)")
    (symbol . "a")
    (requires . 0)
    (cache)
    (limit . nil)
    (action . (lambda ()
                (insert "=\"")
                (auto-complete)))))

(defvar ac-source-nxml-attr-value
  '((candidates . auto-complete-nxml-get-candidates)
    (prefix . "=\\(?:\"\\|'\\)\\s-*\\([^\"':; ]*\\)")
    (symbol . "v")
    (requires . 0)
    (cache)
    (limit . nil)
    (action . (lambda ()
                (auto-complete-nxml-expand-other-xmlns)))))

(defvar ac-source-nxml-css
  '((candidates . auto-complete-nxml-get-css-candidates)
    (prefix . "\\s-+style=\\(?:\"\\|'\\)\\([^\"']*\\)")
    (symbol . "c")
    (requires . 0)
    (cache)
    (limit . nil)
    (action . (lambda ()
                (insert ": ")
                (auto-complete '(ac-source-nxml-css-property))))))

(defvar ac-source-nxml-css-property
  '((candidates . auto-complete-nxml-get-css-candidates)
    (prefix . ac-css-prefix)
    (symbol . "p")
    (requires . 0)
    (cache)
    (limit . nil)
    (action . (lambda ()
                (insert ";")))))

(defvar ac-source-nxml-tag-value
  '((candidates . auto-complete-nxml-get-tag-value-candidates)
    (prefix . ">\\s-*\\([^<]*\\)")
    (symbol . "w")
    (cache)))


(defun auto-complete-nxml-insert-with-ac-trigger-command (n)
  (interactive "p")
  (self-insert-command n)
  (ac-trigger-key-command n))

(defun auto-complete-nxml-setup ()
  (local-set-key (kbd "SPC") 'auto-complete-nxml-insert-with-ac-trigger-command)
  (setq ac-sources '(ac-source-nxml-tag
                     ac-source-nxml-attr
                     ac-source-nxml-attr-value
                     ac-source-nxml-css
                     ac-source-nxml-css-property
                     ac-source-nxml-tag-value))
  (add-to-list 'ac-modes 'nxml-mode)
  (auto-complete-mode))

(add-hook 'nxml-mode-hook 'auto-complete-nxml-setup t)


(provide 'auto-complete-nxml)
;;; auto-complete-nxml.el ends here