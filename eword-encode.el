;;; eword-encode.el --- RFC 2047 based encoded-word encoder for GNU Emacs

;; Copyright (C) 1995,1996,1997,1998 Free Software Foundation, Inc.

;; Author: MORIOKA Tomohiko <morioka@jaist.ac.jp>
;; Keywords: encoded-word, MIME, multilingual, header, mail, news

;; This file is part of FLIM (Faithful Library about Internet Message).

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Code:

(require 'emu)
(require 'mel)
(require 'std11)
(require 'mime-def)
(require 'eword-decode)


;;; @ variables
;;;

(defgroup eword-encode nil
  "Encoded-word encoding"
  :group 'mime)

(defcustom eword-field-encoding-method-alist
  '(("X-Nsubject" . iso-2022-jp-2)
    ("Newsgroups" . nil)
    ("Message-ID" . nil)
    (t            . mime)
    )
  "*Alist to specify field encoding method.
Its key is field-name, value is encoding method.

If method is `mime', this field will be encoded into MIME format.

If method is a MIME-charset, this field will be encoded as the charset
when it must be convert into network-code.

If method is `default-mime-charset', this field will be encoded as
variable `default-mime-charset' when it must be convert into
network-code.

If method is nil, this field will not be encoded."
  :group 'eword-encode
  :type '(repeat (cons (choice :tag "Field"
			       (string :tag "Name")
			       (const :tag "Default" t))
		       (choice :tag "Method"
			       (const :tag "MIME conversion" mime)
			       (symbol :tag "non-MIME conversion")
			       (const :tag "no-conversion" nil)))))

(defvar eword-charset-encoding-alist
  '((us-ascii		. nil)
    (iso-8859-1		. "Q")
    (iso-8859-2		. "Q")
    (iso-8859-3		. "Q")
    (iso-8859-4		. "Q")
    (iso-8859-5		. "Q")
    (koi8-r		. "Q")
    (iso-8859-7		. "Q")
    (iso-8859-8		. "Q")
    (iso-8859-9		. "Q")
    (iso-2022-jp	. "B")
    (iso-2022-kr	. "B")
    (gb2312		. "B")
    (cn-gb		. "B")
    (cn-gb-2312		. "B")
    (euc-kr		. "B")
    (iso-2022-jp-2	. "B")
    (iso-2022-int-1	. "B")
    ))


;;; @ encoded-text encoder
;;;

(defun eword-encode-text (charset encoding string &optional mode)
  "Encode STRING as an encoded-word, and return the result.
CHARSET is a symbol to indicate MIME charset of the encoded-word.
ENCODING allows \"B\" or \"Q\".
MODE is allows `text', `comment', `phrase' or nil.  Default value is
`phrase'."
  (let ((text (encoded-text-encode-string string encoding)))
    (if text
	(concat "=?" (upcase (symbol-name charset)) "?"
		encoding "?" text "?=")
      )))


;;; @ charset word
;;;

(defsubst eword-encode-char-type (character)
  (if (or (eq character ? )(eq character ?\t))
      nil
    (char-charset character)
    ))

(defun eword-encode-divide-into-charset-words (string)
  (let ((len (length string))
	dest)
    (while (> len 0)
      (let* ((chr (sref string 0))
	     (charset (eword-encode-char-type chr))
	     (i (char-length chr)))
	(while (and (< i len)
		    (setq chr (sref string i))
		    (eq charset (eword-encode-char-type chr))
		    )
	  (setq i (char-next-index chr i))
	  )
	(setq dest (cons (cons charset (substring string 0 i)) dest)
	      string (substring string i)
	      len (- len i)
	      )))
    (nreverse dest)
    ))


;;; @ word
;;;

(defun eword-encode-charset-words-to-words (charset-words)
  (let (dest)
    (while charset-words
      (let* ((charset-word (car charset-words))
	     (charset (car charset-word))
	     )
	(if charset
	    (let ((charsets (list charset))
		  (str (cdr charset-word))
		  )
	      (catch 'tag
		(while (setq charset-words (cdr charset-words))
		  (setq charset-word (car charset-words)
			charset (car charset-word))
		  (if (null charset)
		      (throw 'tag nil)
		    )
		  (or (memq charset charsets)
		      (setq charsets (cons charset charsets))
		      )
		  (setq str (concat str (cdr charset-word)))
		  ))
	      (setq dest (cons (cons charsets str) dest))
	      )
	  (setq dest (cons charset-word dest)
		charset-words (cdr charset-words)
		))))
    (nreverse dest)
    ))


;;; @ rule
;;;

(defmacro make-ew-rword (text charset encoding type)
  (` (list (, text)(, charset)(, encoding)(, type))))
(defmacro ew-rword-text (rword)
  (` (car (, rword))))
(defmacro ew-rword-charset (rword)
  (` (car (cdr (, rword)))))
(defmacro ew-rword-encoding (rword)
  (` (car (cdr (cdr (, rword))))))
(defmacro ew-rword-type (rword)
  (` (car (cdr (cdr (cdr (, rword)))))))

(defun tm-eword::find-charset-rule (charsets)
  (if charsets
      (let* ((charset (charsets-to-mime-charset charsets))
	     (encoding (cdr (assq charset eword-charset-encoding-alist)))
	     )
	(list charset encoding)
	)))

(defun tm-eword::words-to-ruled-words (wl &optional mode)
  (mapcar (function
	   (lambda (word)
	     (let ((ret (tm-eword::find-charset-rule (car word))))
	       (make-ew-rword (cdr word) (car ret)(nth 1 ret) mode)
	       )))
	  wl))

(defun tm-eword::space-process (seq)
  (let (prev a ac b c cc)
    (while seq
      (setq b (car seq))
      (setq seq (cdr seq))
      (setq c (car seq))
      (setq cc (ew-rword-charset c))
      (if (null (ew-rword-charset b))
	  (progn
	    (setq a (car prev))
	    (setq ac (ew-rword-charset a))
	    (if (and (ew-rword-encoding a)
		     (ew-rword-encoding c))
		(cond ((eq ac cc)
		       (setq prev (cons
				   (cons (concat (car a)(car b)(car c))
					 (cdr a))
				   (cdr prev)
				   ))
		       (setq seq (cdr seq))
		       )
		      (t
		       (setq prev (cons
				   (cons (concat (car a)(car b))
					 (cdr a))
				   (cdr prev)
				   ))
		       ))
	      (setq prev (cons b prev))
	      ))
	(setq prev (cons b prev))
	))
    (reverse prev)
    ))

(defun eword-encode-split-string (str &optional mode)
  (tm-eword::space-process
   (tm-eword::words-to-ruled-words
    (eword-encode-charset-words-to-words
     (eword-encode-divide-into-charset-words str))
    mode)))


;;; @ length
;;;

(defun tm-eword::encoded-word-length (rword)
  (let ((string   (ew-rword-text     rword))
	(charset  (ew-rword-charset  rword))
	(encoding (ew-rword-encoding rword))
	ret)
    (setq ret
	  (cond ((string-equal encoding "B")
		 (setq string (encode-mime-charset-string string charset))
		 (base64-encoded-length string)
		 )
		((string-equal encoding "Q")
		 (setq string (encode-mime-charset-string string charset))
		 (Q-encoded-text-length string (ew-rword-type rword))
		 )))
    (if ret
	(cons (+ 7 (length (symbol-name charset)) ret) string)
      )))


;;; @ encode-string
;;;

(defun tm-eword::encode-string-1 (column rwl)
  (let* ((rword (car rwl))
	 (ret (tm-eword::encoded-word-length rword))
	 string len)
    (if (null ret)
	(cond ((and (setq string (car rword))
		    (or (<= (setq len (+ (length string) column)) 76)
			(<= column 1))
		    )
	       (setq rwl (cdr rwl))
	       )
	      (t
	       (setq string "\n ")
	       (setq len 1)
	       ))
      (cond ((and (setq len (car ret))
		  (<= (+ column len) 76)
		  )
	     (setq string
		   (eword-encode-text
		    (ew-rword-charset rword)
		    (ew-rword-encoding rword)
		    (cdr ret)
		    (ew-rword-type rword)
		    ))
	     (setq len (+ (length string) column))
	     (setq rwl (cdr rwl))
	     )
	    (t
	     (setq string (car rword))
	     (let* ((p 0) np
		    (str "") nstr)
	       (while (and (< p len)
			   (progn
			     (setq np (char-next-index (sref string p) p))
			     (setq nstr (substring string 0 np))
			     (setq ret (tm-eword::encoded-word-length
					(cons nstr (cdr rword))
					))
			     (setq nstr (cdr ret))
			     (setq len (+ (car ret) column))
			     (<= len 76)
			     ))
		 (setq str nstr
		       p np))
	       (if (string-equal str "")
		   (setq string "\n "
			 len 1)
		 (setq rwl (cons (cons (substring string p) (cdr rword))
				 (cdr rwl)))
		 (setq string
		       (eword-encode-text
			(ew-rword-charset rword)
			(ew-rword-encoding rword)
			str
			(ew-rword-type rword)))
		 (setq len (+ (length string) column))
		 )
	       )))
      )
    (list string len rwl)
    ))

(defun eword-encode-rword-list (column rwl)
  (let (ret dest ps special str ew-f pew-f)
    (while rwl
      (setq ew-f (nth 2 (car rwl)))
      (if (and pew-f ew-f)
	  (setq rwl (cons '(" ") rwl)
		pew-f nil)
	(setq pew-f ew-f)
	)
      (setq ret (tm-eword::encode-string-1 column rwl))
      (setq str (car ret))
      (if (eq (elt str 0) ?\n)
	  (if (eq special ?\()
	      (progn
		(setq dest (concat dest "\n ("))
		(setq ret (tm-eword::encode-string-1 2 rwl))
		(setq str (car ret))
		))
	(cond ((eq special ? )
	       (if (string= str "(")
		   (setq ps t)
		 (setq dest (concat dest " "))
		 (setq ps nil)
		 ))
	      ((eq special ?\()
	       (if ps
		   (progn
		     (setq dest (concat dest " ("))
		     (setq ps nil)
		     )
		 (setq dest (concat dest "("))
		 )
	       )))
      (cond ((string= str " ")
	     (setq special ? )
	     )
	    ((string= str "(")
	     (setq special ?\()
	     )
	    (t
	     (setq special nil)
	     (setq dest (concat dest str))
	     ))
      (setq column (nth 1 ret)
	    rwl (nth 2 ret))
      )
    (list dest column)
    ))


;;; @ converter
;;;

(defun eword-encode-phrase-to-rword-list (phrase)
  (let (token type dest str)
    (while phrase
      (setq token (car phrase))
      (setq type (car token))
      (cond ((eq type 'quoted-string)
	     (setq str (concat "\"" (cdr token) "\""))
	     (setq dest
		   (append dest
			   (list
			    (let ((ret (tm-eword::find-charset-rule
					(find-non-ascii-charset-string str))))
			      (make-ew-rword
			       str (car ret)(nth 1 ret) 'phrase)
			      )
			    )))
	     )
	    ((eq type 'comment)
	     (setq dest
		   (append dest
			   '(("(" nil nil))
			   (tm-eword::words-to-ruled-words
			    (eword-encode-charset-words-to-words
			     (eword-encode-divide-into-charset-words
			      (cdr token)))
			    'comment)
			   '((")" nil nil))
			   ))
	     )
	    (t
	     (setq dest
		   (append dest
			   (tm-eword::words-to-ruled-words
			    (eword-encode-charset-words-to-words
			     (eword-encode-divide-into-charset-words
			      (cdr token))
			     ) 'phrase)))
	     ))
      (setq phrase (cdr phrase))
      )
    (tm-eword::space-process dest)
    ))

(defun eword-encode-addr-seq-to-rword-list (seq)
  (let (dest pname)
    (while seq
      (let* ((token (car seq))
	     (name (car token))
	     )
	(cond ((eq name 'spaces)
	       (setq dest (nconc dest (list (list (cdr token) nil nil))))
	       )
	      ((eq name 'comment)
	       (setq dest
		     (nconc
		      dest
		      (list (list "(" nil nil))
		      (eword-encode-split-string (cdr token) 'comment)
		      (list (list ")" nil nil))
		      ))
	       )
	      ((eq name 'quoted-string)
	       (setq dest
		     (nconc
		      dest
		      (list
		       (list (concat "\"" (cdr token) "\"") nil nil)
		       )))
	       )
	      (t
	       (setq dest
		     (if (or (eq pname 'spaces)
			     (eq pname 'comment))
			 (nconc dest (list (list (cdr token) nil nil)))
		       (nconc (butlast dest)
			      (list
			       (list (concat (car (car (last dest)))
					     (cdr token))
				     nil nil)))))
	       ))
	(setq seq (cdr seq)
	      pname name))
      )
    dest))

(defun eword-encode-phrase-route-addr-to-rword-list (phrase-route-addr)
  (if (eq (car phrase-route-addr) 'phrase-route-addr)
      (let ((phrase (nth 1 phrase-route-addr))
	    (route (nth 2 phrase-route-addr))
	    dest)
	(if (eq (car (car phrase)) 'spaces)
	    (setq phrase (cdr phrase))
	  )
	(setq dest (eword-encode-phrase-to-rword-list phrase))
	(if dest
	    (setq dest (append dest '((" " nil nil))))
	  )
	(append
	 dest
	 (eword-encode-addr-seq-to-rword-list
	  (append '((specials . "<"))
		  route
		  '((specials . ">"))))
	 ))))

(defun eword-encode-addr-spec-to-rword-list (addr-spec)
  (if (eq (car addr-spec) 'addr-spec)
      (eword-encode-addr-seq-to-rword-list (cdr addr-spec))
    ))

(defun eword-encode-mailbox-to-rword-list (mbox)
  (let ((addr (nth 1 mbox))
	(comment (nth 2 mbox))
	dest)
    (setq dest (or (eword-encode-phrase-route-addr-to-rword-list addr)
		   (eword-encode-addr-spec-to-rword-list addr)
		   ))
    (if comment
	(setq dest
	      (append dest
		      '((" " nil nil)
			("(" nil nil))
		      (eword-encode-split-string comment 'comment)
		      '((")" nil nil))
		      )))
    dest))

(defsubst eword-encode-addresses-to-rword-list (addresses)
  (let ((dest (eword-encode-mailbox-to-rword-list (car addresses))))
    (if dest
	(while (setq addresses (cdr addresses))
	  (setq dest
		(append dest
			'(("," nil nil))
			'((" " nil nil))
			(eword-encode-mailbox-to-rword-list (car addresses))
			))
	  ))
    dest))

(defsubst eword-encode-msg-id-to-rword-list (msg-id)
  (cons '("<" nil nil)
	(append (eword-encode-addr-seq-to-rword-list (cdr msg-id))
		'((">" nil nil)))))

(defsubst eword-encode-in-reply-to-to-rword-list (in-reply-to)
  (let (dest)
    (while in-reply-to
      (setq dest
	    (append dest
		    (let ((elt (car in-reply-to)))
		      (if (eq (car elt) 'phrase)
			  (eword-encode-phrase-to-rword-list (cdr elt))
			(eword-encode-msg-id-to-rword-list elt)
			))))
      (setq in-reply-to (cdr in-reply-to)))
    dest))


;;; @ application interfaces
;;;

(defcustom eword-encode-default-start-column 10
  "Default start column if it is omitted."
  :group 'eword-encode
  :type 'integer)

(defun eword-encode-string (string &optional column mode)
  "Encode STRING as encoded-words, and return the result.
Optional argument COLUMN is start-position of the field.
Optional argument MODE allows `text', `comment', `phrase' or nil.
Default value is `phrase'."
  (car (eword-encode-rword-list
	(or column eword-encode-default-start-column)
	(eword-encode-split-string string mode))))

(defun eword-encode-address-list (string &optional column)
  "Encode header field STRING as list of address, and return the result.
Optional argument COLUMN is start-position of the field."
  (car (eword-encode-rword-list
	(or column eword-encode-default-start-column)
	(eword-encode-addresses-to-rword-list
	 (std11-parse-addresses-string string))
	)))

(defun eword-encode-in-reply-to (string &optional column)
  "Encode header field STRING as In-Reply-To field, and return the result.
Optional argument COLUMN is start-position of the field."
  (car (eword-encode-rword-list
	(or column 13)
	(eword-encode-in-reply-to-to-rword-list
	 (std11-parse-in-reply-to
	  (std11-lexical-analyze string))))))

(defun eword-encode-structured-field-body (string &optional column)
  "Encode header field STRING as structured field, and return the result.
Optional argument COLUMN is start-position of the field."
  (car (eword-encode-rword-list
	(or column eword-encode-default-start-column)
	(eword-encode-addr-seq-to-rword-list (std11-lexical-analyze string))
	)))

(defun eword-encode-unstructured-field-body (string &optional column)
  "Encode header field STRING as unstructured field, and return the result.
Optional argument COLUMN is start-position of the field."
  (car (eword-encode-rword-list
	(or column eword-encode-default-start-column)
	(eword-encode-split-string string 'text))))

(defun eword-encode-field (string)
  "Encode header field STRING, and return the result.
A lexical token includes non-ASCII character is encoded as MIME
encoded-word.  ASCII token is not encoded."
  (setq string (std11-unfold-string string))
  (let ((ret (string-match std11-field-head-regexp string)))
    (or (if ret
	    (let ((field-name (substring string 0 (1- (match-end 0))))
		  (field-body (eliminate-top-spaces
			       (substring string (match-end 0))))
		  field-name-symbol)
	      (if (setq ret
			(cond ((string= field-body "") "")
			      ((memq (setq field-name-symbol
					   (intern (capitalize field-name)))
				     '(Reply-To
				       From Sender
				       Resent-Reply-To Resent-From
				       Resent-Sender To Resent-To
				       Cc Resent-Cc Bcc Resent-Bcc
				       Dcc))
                               (eword-encode-address-list
				field-body (+ (length field-name) 2))
			       )
			      ((eq field-name-symbol 'In-Reply-To)
                               (eword-encode-in-reply-to
				field-body (+ (length field-name) 2))
			       )
			      ((memq field-name-symbol
				     '(Mime-Version User-Agent))
                               (eword-encode-structured-field-body
				field-body (+ (length field-name) 2))
			       )
			      (t
                               (eword-encode-unstructured-field-body
				field-body (1+ (length field-name)))
			       ))
			)
		  (concat field-name ": " ret)
		)))
	(eword-encode-string string 0)
	)))

(defun eword-in-subject-p ()
  (let ((str (std11-field-body "Subject")))
    (if (and str (string-match eword-encoded-word-regexp str))
	str)))

(defsubst eword-find-field-encoding-method (field-name)
  (setq field-name (downcase field-name))
  (let ((alist eword-field-encoding-method-alist))
    (catch 'found
      (while alist
	(let* ((pair (car alist))
	       (str (car pair)))
	  (if (and (stringp str)
		   (string= field-name (downcase str)))
	      (throw 'found (cdr pair))
	    ))
	(setq alist (cdr alist)))
      (cdr (assq t eword-field-encoding-method-alist))
      )))

(defun eword-encode-header (&optional code-conversion)
  "Encode header fields to network representation, such as MIME encoded-word.

It refer variable `eword-field-encoding-method-alist'."
  (interactive "*")
  (save-excursion
    (save-restriction
      (std11-narrow-to-header mail-header-separator)
      (goto-char (point-min))
      (let ((default-cs (mime-charset-to-coding-system default-mime-charset))
	    beg end field-name)
	(while (re-search-forward std11-field-head-regexp nil t)
	  (setq beg (match-beginning 0))
	  (setq field-name (buffer-substring beg (1- (match-end 0))))
	  (setq end (std11-field-end))
	  (and (find-non-ascii-charset-region beg end)
	       (let ((method (eword-find-field-encoding-method
			      (downcase field-name))))
		 (cond ((eq method 'mime)
			(let ((field
			       (buffer-substring-no-properties beg end)
			       ))
			  (delete-region beg end)
			  (insert (eword-encode-field field))
			  ))
		       (code-conversion
			(let ((cs
			       (or (mime-charset-to-coding-system
				    method)
				   default-cs)))
			  (encode-coding-region beg end cs)
			  )))
		 ))
	  ))
      )))


;;; @ end
;;;

(provide 'eword-encode)

;;; eword-encode.el ends here
