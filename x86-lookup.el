;;; x86-lookup.el --- jump to x86 instruction documentation -*- lexical-binding: t; -*-

;; This is free and unencumbered software released into the public domain.

;; Author: Christopher Wellons <wellons@nullprogram.com>
;; URL: https://github.com/skeeto/x86-lookup
;; Version: 1.0.0
;; Package-Requires: ((emacs "24.3") (cl-lib "0.3"))

;;; Commentary:

;; Requires the following:
;; * pdftotext command line program from Poppler
;; * Intel 64 and IA-32 Architecture Software Developer Manual PDF

;; http://www.intel.com/content/www/us/en/processors/architectures-software-developer-manuals.html

;; Building the index specifically requires Poppler's pdftotext, not
;; just any PDF to text converter. It has a critical feature over the
;; others: conventional line feed characters (U+000C) are output
;; between pages, allowing precise tracking of page numbers. These are
;; the markers Emacs uses for `forward-page' and `backward-page'.

;; Your copy of the manual must contain the full instruction set
;; reference in a single PDF. Set `x86-lookup-pdf' to this file name.
;; Intel optionally offers the instruction set reference in two
;; separate volumes, but don't use that.

;; Choose a PDF viewer by setting `x86-lookup-browse-pdf-function'. If
;; you provide a custom function, your PDF viewer should support
;; linking to a specific page (e.g. not supported by xdg-open,
;; unfortunately). Otherwise there's no reason to use this package.

;; Once configured, the main entrypoint is `x86-lookup'. You may want
;; to bind this to a key. The interactive prompt will default to the
;; mnemonic under the point. Here's a suggestion:

;;   (global-set-key (kbd "C-h x") #'x86-lookup)

;; This package pairs well with `nasm-mode'!

;;; Code

(require 'cl-lib)

(defvar x86-lookup-pdf nil
  "Path to Intel's manual containing the instruction set reference.")

(defvar x86-lookup-pdftotext-program "pdftotext"
  "Path to pdftotext, part of Popper.")

(defvar x86-lookup-browse-pdf-function #'x86-lookup-browse-pdf-any
  "A function that launches a PDF viewer at a specific page.
This function accepts two arguments: filename and page number.")

(defvar x86-lookup-index nil
  "Alist mapping instructions to page numbers.")

(defvar x86-lookup--expansions
  '(("h$" "" "nta" "t0" "t1" "t2" "w" "wt1")
    ("cc$" "a" "ae" "b" "be" "c" "cxz" "e" "ecxz" "g" "ge" "l" "le" "mp"
           "mpe" "na" "nae" "nb" "nbe" "nc" "ne" "ng" "nge" "nl" "nle"
           "no" "np" "ns" "nz" "o" "p" "pe" "po" "rcxz" "s" "z")
    ("$" "")) ; fallback "match"
  "How to expand mnemonics into multiple mnemonics.")

(defun x86-lookup--expand (names page)
  "Expand string of PDF-sourced mnemonics into user-friendly mnemonics."
  (let ((case-fold-search nil)
        (rev-string-match-p (lambda (s re) (string-match-p re s))))
    (cl-loop for mnemonic in (split-string names "/")
             for match = (cl-assoc mnemonic x86-lookup--expansions
                                   :test rev-string-match-p)
             for chop-point = (string-match-p (car match) mnemonic)
             for tails = (cdr match)
             for chopped = (downcase (substring mnemonic 0 chop-point))
             nconc (cl-loop for tail in tails
                            collect (cons (concat chopped tail) page)))))

(cl-defun x86-lookup-create-index (&optional (pdf x86-lookup-pdf))
  "Create an index alist from PDF mapping mnemonics to page numbers.
This function requires the pdftotext command line program."
  (let ((mnemonic (concat "INSTRUCTION SET REFERENCE, [A-Z]-[A-Z]\n\n"
                          "\\([A-Za-z/]+\\) ?—"))
        (case-fold-search nil))
    (with-temp-buffer
      (call-process x86-lookup-pdftotext-program nil t nil
                    (file-truename pdf) "-")
      (setf (point) (point-min))
      (cl-loop for page upfrom 1
               while (< (point) (point-max))
               when (looking-at mnemonic)
               nconc (x86-lookup--expand (match-string 1) page) into index
               do (forward-page)
               finally (cl-return (cl-remove-duplicates
                                   index :key #'car :test #'string=))))))

(defun x86-lookup-ensure-index ()
  "Ensure the PDF index has been created, returning the index."
  (if (null x86-lookup-index)
      (if (not (and x86-lookup-pdf (file-exists-p x86-lookup-pdf)))
        (error "No PDF available. Set `x86-lookup-pdf'.")
      (message "Generating mnemonic index ...")
      (setf x86-lookup-index (x86-lookup-create-index)))
    x86-lookup-index))

(defun x86-lookup-browse-pdf (pdf page)
  "Launch a PDF viewer using `x86-lookup-browse-pdf-function'."
  (funcall x86-lookup-browse-pdf-function pdf page))

(defun x86-lookup (mnemonic)
  "Jump to the PDF documentation for MNEMONIC.
Defaults to the mnemonic under point."
  (interactive
   (progn
     (x86-lookup-ensure-index)
     (let* ((mnemonics (mapcar #'car x86-lookup-index))
            (thing (thing-at-point 'word))
            (mnemonic (if (member thing mnemonics) thing nil)))
       (list
        (completing-read "Mnemonic: " mnemonics nil t nil nil mnemonic)))))
  (let ((page (cdr (assoc mnemonic x86-lookup-index))))
    (x86-lookup-browse-pdf (file-truename x86-lookup-pdf) page)))

;; PDF viewers:

(defun x86-lookup-browse-pdf-xpdf (pdf page)
  "View PDF at PAGE using xpdf."
  (start-process "xpdf" nil "xpdf" "--" pdf (format "%d" page)))

(defun x86-lookup-browse-pdf-evince (pdf page)
  "View PDF at PAGE using Evince."
  (start-process "evince" nil "evince" "-p" (format "%d" page) "--" pdf))

(defun x86-lookup-browse-pdf-okular (pdf page)
  "View PDF at PAGE file using Okular."
  (start-process "okular" nil "okular" "-p" (format "%d" page) "--" pdf))

(defun x86-lookup-browse-pdf-gv (pdf page)
  "View PDF at PAGE using gv."
  (start-process "gv" nil "gv" "-nocenter" (format "-page=%d" page) "--" pdf))

(defun x86-lookup-browse-pdf-browser (pdf page)
  "Visit PDF using `browse-url' with a fragment for the PAGE."
  (browse-url (format "file://%s#%d" pdf page)))

(defun x86-lookup-browse-pdf-any (pdf page)
  "Try visiting PDF using the first viewer found."
  ;; Ordered by my personal preference.
  (or (ignore-errors (x86-lookup-browse-pdf-evince pdf page))
      (ignore-errors (x86-lookup-browse-pdf-xpdf pdf page))
      (ignore-errors (x86-lookup-browse-pdf-okular pdf page))
      (ignore-errors (x86-lookup-browse-pdf-gv pdf page))
      (x86-lookup-browse-pdf-browser pdf page)))

(provide 'x86-lookup)

;;; x86-lookup.el ends here
