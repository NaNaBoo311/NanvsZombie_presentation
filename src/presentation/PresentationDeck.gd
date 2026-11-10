class_name PresentationDeck
extends RefCounted

# PresentationDeck — the presentation's copy, in one place. The cover reads its
# course, title, tagline and credits from here; the contents and section screens
# added next read their headings from the same file.
#
# Copy follows the title and team slides in reports/GameProgramming_slide_latex
# (sections 01 and 02) and the GDD's one-line pitch. Scene scripts never repeat it.
# The presenter order below is the credit order on the cover.

const UNIVERSITY_EYEBROW := "HO CHI MINH CITY"
const UNIVERSITY := "University of Technology"
const FACULTY := "Faculty of Computer Science and Engineering"
const COURSE := "Game Programming (CO3045) · CC02"

const TITLE_FIRST := "Leyline"
const TITLE_SECOND := "Warden"
const SUBTITLE := "Spirits of the Soil"
const TAGLINE := "A 3D tower defence set in a miniature Vietnam."

const CREDITS_LABEL := "PRESENTED BY"
const PRESENTERS := [
	{"name": "Phạm Nam An", "id": "2352016"},
	{"name": "Hồ Minh Nhật", "id": "2352858"},
	{"name": "Lê Phạm Tiến Long", "id": "2352688"},
]
const LECTURER_LABEL := "LECTURER"
const LECTURER := "Phan Trần Minh Khuê"
const DATE := "11 November 2026"
