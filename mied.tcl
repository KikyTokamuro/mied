#!/usr/bin/env tclsh
#
# Mied - a small editor on Tcl/Tk.
#
# MIT License
#
# Copyright (c) 2026 Daniil Arkhangelsky (Kiky Tokamuro)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Changelog
#     -          version 0.2.0 Added About window
#     2026-08-28 version 0.1.1 fixing PlaceResizeHandle with MinimizeWindow
#                              fixing ToggleMaximize with MinimizeWindow
#     2026-08-22 version 0.1

package require Tk
package require ctext

set Mied(version) "0.2.0"
set Mied(authors) "Daniil Arkhangelsky (Kiky Tokamuro)"
set Mied(license) "MIT License, 2026"

# --- Application state ----------------------------------------------------

array set Buffers {}          ;# per-buffer fields: id,name,path,content,...
set ActiveBufferId ""         ;# target of Save / Find / highlighting extras
set ZIndex 100                ;# stacking counter used with raise
set CreatingBuffer 0          ;# debounce for New/Open on a held hotkey
set SidebarVisible 0

set FindPattern ""
set ReplacePattern ""
set FindCaseSensitive 0

# --- Layout ---------------------------------------------------------------

set Layout(toolbar_h) 32
set Layout(sidebar_w) 180
set Layout(gap)       2       ;# gutter between sidebar and desktop

# --- Theme ----------------------------------------------------------------

set Config(accent)       "#5d7e73"
set Config(bg)           "#e8e8e8"
set Config(fg)           "#666666"
set Config(toolbar_bg)   "#c8c8c8"
set Config(sidebar_bg)   "#c8c8c8"
set Config(window_bg)    "#ffffff"
set Config(titlebar_bg)  "#c8c8c8"
set Config(border)       "#aaaaaa"
set Config(font)         {"Fira Code" 9}
set Config(font_bold)    {"Fira Code" 9 bold}
set Config(ui_font)      {"Fira Code" 9}
set Config(status_fg)    "#666666"
set Config(close_hover)  "#cc0000"
set Config(min_hover)    "#5d7e73"
set Config(btn_hover_bg) "#bbbbbb"
set Config(hover_fg)     "#000000"
set Config(title_fg)     "#444444"
set Config(list_fg)      "#444444"
set Config(insert_color) "#000000"
set Config(sel_bg)       "#5d7e73"
set Config(sel_fg)       "#ffffff"
set Config(scroll_bg)    "#cccccc"
set Config(header_fg)    "#666666"
set Config(linenum_bg)   "#f0f0f0"
set Config(linenum_fg)   "#888888"

# Monochrome highlight: dark ink for structure, lighter gray for asides.
set Config(hl_keyword)   "#222222"
set Config(hl_comment)   "#9a9a9a"
set Config(hl_string)    "#555555"
set Config(hl_number)    "#333333"
set Config(hl_punct)     "#777777"
set Config(hl_preproc)   "#444444"

# --- Helpers --------------------------------------------------------------

# True if the buffer window for id is still mapped.
proc SafeWindowExists {id} {
    global Buffers
    return [expr {[info exists Buffers($id,window)] && [winfo exists $Buffers($id,window)]}]
}

# Sorted list of live buffer ids.
proc AllBufferIds {} {
    global Buffers
    set ids [list]
    foreach name [array names Buffers *,id] {
        lappend ids $Buffers($name)
    }
    return [lsort -integer $ids]
}

# Lowest unused positive id (reused after close so untitled-N stays compact).
proc AllocBufferId {} {
    set id 1
    foreach used [AllBufferIds] {
        if {$used != $id} {
            return $id
        }
        incr id
    }
    return $id
}

# Places .sidebar / .desktop with a toolbar offset and a sidebar gutter.
proc PlaceDesktop {} {
    global SidebarVisible Layout

    set th $Layout(toolbar_h)
    set sw $Layout(sidebar_w)
    set gap $Layout(gap)

    if {$SidebarVisible} {
        place .sidebar -x 0 -y $th -width $sw -relheight 1 -height -$th
        set dx [expr {$sw + $gap - 1}]
        place .desktop -x $dx -y $th -relwidth 1 -width -$dx -relheight 1 -height -$th
    } else {
        place forget .sidebar
        place .desktop -x 0 -y $th -relwidth 1 -width 0 -relheight 1 -height -$th
    }
}

# Geometry of a maximized buffer: inset by Layout(gap) so the desktop
# background shows as a rim (same idea as the strip under the toolbar).
proc MaximizedGeom {} {
    global Desktop Layout
    set g $Layout(gap)
    set dw [winfo width $Desktop]
    set dh [winfo height $Desktop]
    return [list $g $g [expr {max(50, $dw - 2 * $g)}] [expr {max(50, $dh - 2 * $g)}]]
}

# Pins the resize grip above the status bar (and findbar, if shown).
proc PlaceResizeHandle {id} {
	global Buffers
	if {![SafeWindowExists $id]} return
	if {![info exists Buffers($id,visible)] || !$Buffers($id,visible)} return

    set win $Buffers($id,window)
    set yOff -22
    if {[info exists Buffers($id,findbar)] && $Buffers($id,findbar)} {
        set yOff -48
    }
    place $win.resize -relx 1.0 -rely 1.0 -anchor se -y $yOff
    raise $win.resize
}

# Flat canvas button. Uses grid when -row/-column is present, otherwise pack.
proc MakeFlatButton {parent name width height text font bg fg hover_bg hover_fg cmd geomopts} {
    set path ${parent}.${name}
    canvas $path -width $width -height $height -bg $bg \
        -highlightthickness 0 -cursor hand2

    set isGrid 0
    foreach opt $geomopts {
        if {[string match "-row*" $opt] || [string match "-column*" $opt]} {
            set isGrid 1
            break
        }
    }
    if {$isGrid} {
        grid $path {*}$geomopts
    } else {
        pack $path {*}$geomopts
    }

    $path create rectangle 0 0 $width $height -fill $bg -outline "" -tags {hit bg}
    $path create text [expr {$width / 2}] [expr {$height / 2}] \
        -text $text -fill $fg -font $font -tags {hit label}

    $path bind hit <Button-1> $cmd

    $path bind hit <Enter> [list apply {{path hover_bg} {
        $path configure -bg $hover_bg
        $path itemconfigure bg -fill $hover_bg
    }} $path $hover_bg]
    $path bind hit <Leave> [list apply {{path bg} {
        $path configure -bg $bg
        $path itemconfigure bg -fill $bg
    }} $path $bg]

    if {$hover_fg ne ""} {
        $path bind hit <Enter> +[list $path itemconfigure label -fill $hover_fg]
        $path bind hit <Leave> +[list $path itemconfigure label -fill $fg]
    }

    return $path
}

# Toolbar button with a fixed 24px height.
proc MakeToolbarButton {name width text cmd} {
    global Config
    MakeFlatButton .toolbar.inner $name $width 24 $text \
        $Config(ui_font) $Config(toolbar_bg) $Config(fg) \
        $Config(btn_hover_bg) $Config(hover_fg) $cmd \
        [list -side left -padx 2 -pady 3]
}

# --- Syntax highlighting --------------------------------------------------

# Language from extension or shebang: tcl, c, sh, or empty.
proc DetectLanguage {path content} {
    set ext [string tolower [file extension $path]]
    switch -- $ext {
        .tcl - .tk - .itcl - .tm { return tcl }
        .c - .h - .cpp - .cc - .cxx - .hpp { return c }
        .sh - .bash - .ksh - .zsh { return sh }
    }
    set line [string trim [lindex [split $content \n] 0]]
    if {[string match "#!*" $line]} {
        if {[string match "*tclsh*" $line] || [string match "*wish*" $line]} {
            return tcl
        }
        if {[string match "*bash*" $line] || [string match "*dash*" $line] \
                || [regexp {/bin/(ba|k|z)?sh} $line]} {
            return sh
        }
    }
    return ""
}

# Comment prefix used by Ctrl+/.
proc CommentPrefix {lang} {
    switch -- $lang {
        c { return "//" }
        default { return "#" }
    }
}

# Drop previous ctext classes and install a monochrome set for lang.
proc ApplySyntaxHighlighting {ctext lang} {
    global Config

    catch {::ctext::clearHighlightClasses $ctext}
    catch {::ctext::disableComments $ctext}

    if {$lang eq ""} {
        $ctext highlight 1.0 end
        return
    }

    set kw $Config(hl_keyword)
    set cm $Config(hl_comment)
    set st $Config(hl_string)
    set nu $Config(hl_number)
    set pu $Config(hl_punct)
    set pp $Config(hl_preproc)

    switch -- $lang {
        tcl {
            ::ctext::addHighlightClass $ctext keywords $kw {
                proc method constructor destructor namespace package require
                if else elseif then switch while for foreach break continue
                return catch error try trap finally throw expr eval uplevel
                upvar global variable set unset lappend lindex llength lrange
                lsearch lsort lreplace linsert concat join split string
                array dict info interp rename apply yield coroutine
                source open close read puts gets seek tell eof fconfigure
                bind bindtags event after update winfo wm pack grid place
                frame toplevel label button entry listbox canvas text
                checkbutton radiobutton scale scrollbar menu menubutton
                ttk::frame ttk::button ttk::entry ttk::label ttk::scrollbar
                incr append subst regexp regsub scan format clock file
                cd pwd glob exec pid exit return -code
            }
            ::ctext::addHighlightClassWithOnlyCharStart $ctext vars $pu "\$"
            ::ctext::addHighlightClassForSpecialChars $ctext punct $pu {[]{}\\}
            ::ctext::addHighlightClassForRegexp $ctext strings $st {"(\\.|[^"\\])*"}
            ::ctext::addHighlightClassForRegexp $ctext comments $cm {#[^\n\r]*}
        }
        c {
            ::ctext::addHighlightClass $ctext keywords $kw {
                auto break case char const continue default do double else
                enum extern float for goto if inline int long register
                restrict return short signed sizeof static struct switch
                typedef union unsigned void volatile while _Bool _Complex
                _Imaginary include define ifdef ifndef endif pragma undef
                true false NULL
            }
            catch {::ctext::enableComments $ctext}
            ::ctext::addHighlightClassForRegexp $ctext comments $cm {//[^\n\r]*}
            ::ctext::addHighlightClassForRegexp $ctext preproc $pp {^[[:space:]]*#[[:space:]]*[a-zA-Z]+}
            ::ctext::addHighlightClassForRegexp $ctext strings $st {"(\\.|[^"\\])*"}
            ::ctext::addHighlightClassForRegexp $ctext chars $st {'(\\.|[^'\\])'}
            ::ctext::addHighlightClassForRegexp $ctext numbers $nu {\m[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?\M}
            ::ctext::addHighlightClassForSpecialChars $ctext punct $pu {()[]{};,}
        }
        sh {
            ::ctext::addHighlightClass $ctext keywords $kw {
                if then else elif fi case esac for in do done while until
                function return break continue exit export local readonly
                unset shift trap eval exec source alias unalias test
                echo printf read cd pwd set unset declare typeset
            }
            ::ctext::addHighlightClassWithOnlyCharStart $ctext vars $pu "\$"
            ::ctext::addHighlightClassForRegexp $ctext strings $st {"(\\.|[^"\\])*"}
            ::ctext::addHighlightClassForRegexp $ctext squote $st {'[^']*'}
            ::ctext::addHighlightClassForRegexp $ctext comments $cm {#[^\n\r]*}
            ::ctext::addHighlightClassForSpecialChars $ctext punct $pu {[]{}();|}
        }
    }

    $ctext tag configure keywords -font $Config(font_bold) -foreground $kw
    $ctext tag configure comments -font $Config(font) -foreground $cm
    $ctext highlight 1.0 end
}

# Detect language from path/content and restyle the widget.
proc ApplySyntaxForBuffer {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set content $Buffers($id,content)
    if {[SafeWindowExists $id]} {
        set content [$Buffers($id,window).content.ctext get 1.0 end-1c]
    }
    set lang [DetectLanguage $Buffers($id,path) $content]
    set Buffers($id,lang) $lang
    ApplySyntaxHighlighting $Buffers($id,window).content.ctext $lang
    UpdateLineCounter $id
}

# --- Buffer lifecycle -----------------------------------------------------

# Create a buffer, its window, and make it active. Empty name → untitled-N.
proc CreateBuffer {name path content} {
    global Buffers CreatingBuffer

    if {$CreatingBuffer} return
    set CreatingBuffer 1

    set id [AllocBufferId]
    if {$name eq ""} {
        set name "untitled-$id"
    }

    set Buffers($id,id)        $id
    set Buffers($id,name)      $name
    set Buffers($id,path)      $path
    set Buffers($id,content)   $content
    set Buffers($id,modified)  0
    set Buffers($id,visible)   1
    set Buffers($id,maximized) 0
    set Buffers($id,findbar)   0
    set Buffers($id,lang)      [DetectLanguage $path $content]

    CreateWindow $id
    UpdateBufferList
    SetActiveBuffer $id

    after 100 {set ::CreatingBuffer 0}
    return $id
}

# Empty untitled buffer.
proc NewBuffer {} {
    CreateBuffer "" "" ""
}

# Build the Tk window: titlebar, ctext, scrollbars, status, findbar.
proc CreateWindow {id} {
    global Buffers Config Desktop

    set win $Desktop.buffer$id
    set Buffers($id,window) $win

    set x [expr {20 + ($id % 5) * 30}]
    set y [expr {20 + ($id % 5) * 25}]

    frame $win -bg $Config(border) -bd 1 -relief flat

    frame $win.titlebar -bg $Config(titlebar_bg) -height 26 -cursor fleur
    grid $win.titlebar -row 0 -column 0 -sticky ew

    MakeFlatButton $win.titlebar minbtn 20 20 "_" \
        $Config(ui_font) $Config(titlebar_bg) $Config(status_fg) \
        $Config(titlebar_bg) $Config(min_hover) [list MinimizeWindow $id] \
        [list -side right -padx 2]

    MakeFlatButton $win.titlebar closebtn 20 20 "x" \
        $Config(ui_font) $Config(titlebar_bg) $Config(status_fg) \
        $Config(titlebar_bg) $Config(close_hover) [list CloseBuffer $id] \
        [list -side right -padx 6]

    label $win.titlebar.label -text "$Buffers($id,name)" \
        -bg $Config(titlebar_bg) -fg $Config(title_fg) \
        -font $Config(ui_font) -anchor w
    pack $win.titlebar.label -side left -padx 8 -pady 2 -fill x -expand 1

    frame $win.content -bg $Config(window_bg)
    grid $win.content -row 1 -column 0 -sticky nsew

    ctext $win.content.ctext -bg $Config(window_bg) -fg $Config(fg) \
        -font $Config(font) -wrap none \
        -yscrollcommand [list $win.content.vsb set] \
        -xscrollcommand [list $win.content.hsb set] \
        -undo 1 -maxundo 100 \
        -insertbackground $Config(insert_color) \
        -selectbackground $Config(sel_bg) \
        -selectforeground $Config(sel_fg) \
        -borderwidth 0 -highlightthickness 0 \
        -padx 4 -pady 4 \
        -linemap 1 \
        -linemapfg $Config(linenum_fg) \
        -linemapbg $Config(linenum_bg) \
        -linemap_select_fg $Config(sel_fg) \
        -linemap_select_bg $Config(sel_bg) \
        -tabs [font measure $Config(font) "    "]

    $win.content.ctext tag configure found \
        -background $Config(accent) \
        -foreground $Config(insert_color)
    $win.content.ctext tag raise found

    ttk::scrollbar $win.content.vsb -orient vertical \
        -command [list $win.content.ctext yview]
    ttk::scrollbar $win.content.hsb -orient horizontal \
        -command [list $win.content.ctext xview]

    grid $win.content.ctext -row 0 -column 0 -sticky nsew
    grid $win.content.vsb   -row 0 -column 1 -sticky ns
    grid $win.content.hsb   -row 1 -column 0 -sticky ew
    grid rowconfigure    $win.content 0 -weight 1
    grid columnconfigure $win.content 0 -weight 1

    ttk::style configure Vertical.TScrollbar   -background $Config(scroll_bg)
    ttk::style configure Horizontal.TScrollbar -background $Config(scroll_bg)

    frame $win.resize -bg $Config(border) -width 17 -height 15 -cursor sizing

    frame $win.statusbar -bg $Config(titlebar_bg) -height 22
    grid $win.statusbar -row 2 -column 0 -sticky ew

    label $win.statusbar.lines -text "Ln 1, Col 1" \
        -bg $Config(titlebar_bg) -fg $Config(status_fg) \
        -font $Config(ui_font) -anchor w
    pack $win.statusbar.lines -side left -padx 8

    label $win.statusbar.lang -text "" \
        -bg $Config(titlebar_bg) -fg $Config(status_fg) \
        -font $Config(ui_font) -anchor e
    pack $win.statusbar.lang -side right -padx 8

    label $win.statusbar.info -text "" \
        -bg $Config(titlebar_bg) -fg $Config(status_fg) \
        -font $Config(ui_font) -anchor e
    pack $win.statusbar.info -side right -padx 8

    frame $win.findbar -bg $Config(toolbar_bg) -height 26
    grid columnconfigure $win.findbar 0 -weight 1 -minsize 30
    grid columnconfigure $win.findbar 1 -weight 1 -minsize 30

    entry $win.findbar.find -textvariable ::FindPattern \
        -bg $Config(window_bg) -fg $Config(fg) -font $Config(ui_font) \
        -highlightthickness 1 -highlightcolor $Config(accent)
    grid $win.findbar.find -row 0 -column 0 -sticky ew -padx 2 -pady 2

    entry $win.findbar.replace -textvariable ::ReplacePattern \
        -bg $Config(window_bg) -fg $Config(fg) -font $Config(ui_font) \
        -highlightthickness 1 -highlightcolor $Config(accent)
    grid $win.findbar.replace -row 0 -column 1 -sticky ew -padx 2 -pady 2

    MakeFlatButton $win.findbar btn_case 26 22 "Aa" \
        $Config(ui_font) $Config(toolbar_bg) $Config(fg) \
        $Config(btn_hover_bg) $Config(hover_fg) ToggleFindCase \
        [list -row 0 -column 2 -padx 1 -pady 2]
    StyleCaseButton $win.findbar.btn_case

    set findbarButtons {
        {prev   26 "<"     FindPrevInBuffer}
        {next   26 ">"     FindNextInBuffer}
        {repl   42 "Repl"  ReplaceInBuffer}
        {all    30 "ReAll" ReplaceAllInBuffer}
        {close  22 "x"     HideFindBar}
    }
    set col 3
    foreach btn $findbarButtons {
        lassign $btn bname bwidth btext bcmd

        if {$bname eq "close"} {
            set btnFg $Config(close_hover)
            set btnHoverFg $Config(close_hover)
        } else {
            set btnFg $Config(fg)
            set btnHoverFg $Config(hover_fg)
        }

        MakeFlatButton $win.findbar btn_$bname $bwidth 22 $btext \
            $Config(ui_font) $Config(toolbar_bg) $btnFg \
            $Config(btn_hover_bg) $btnHoverFg [list $bcmd $id] \
            [list -row 0 -column $col -padx 1 -pady 2]

        incr col
    }

    bind $win.findbar.find    <Return>  [list FindNextInBuffer $id]
    bind $win.findbar.replace <Return>  [list ReplaceInBuffer $id]
    bind $win.findbar         <Escape>  [list HideFindBar $id]

    grid rowconfigure    $win 1 -weight 1
    grid columnconfigure $win 0 -weight 1

    bind $win.content.ctext <KeyRelease>      +[list UpdateLineCounter $id]
    bind $win.content.ctext <ButtonRelease-1> +[list UpdateLineCounter $id]
    bind $win.content.ctext <<Modified>>      +[list OnTextChange $id]

    place $win -x $x -y $y -width 500 -height 350
    PlaceResizeHandle $id
    raise $win
    incr ::ZIndex

    bind $win.titlebar <ButtonPress-1>   [list StartDrag %W %X %Y $id]
    bind $win.titlebar <B1-Motion>       [list OnDrag %W %X %Y $id]
    bind $win.titlebar <Double-Button-1> [list ToggleMaximize $id]

    bind $win.titlebar.label <ButtonPress-1>   [list StartDrag %W %X %Y $id]
    bind $win.titlebar.label <B1-Motion>       [list OnDrag %W %X %Y $id]
    bind $win.titlebar.label <Double-Button-1> [list ToggleMaximize $id]

    bind $win.resize <ButtonPress-1> [list StartResize %W %X %Y $id]
    bind $win.resize <B1-Motion>     [list OnResize %W %X %Y $id]

    bind $win               <Button-1> [list ActivateWindow $id]
    bind $win.content.ctext <Button-1> +[list ActivateWindow $id]

    bind $win.content.ctext <Control-s>     [list SaveBuffer $id]
    bind $win.content.ctext <Control-w>     [list CloseBuffer $id]
    bind $win.content.ctext <Control-f>     [list ShowFindBar $id]
    bind $win.content.ctext <Control-l>     [list SelectCurrentLine $id]
    bind $win.content.ctext <Control-slash> [list ToggleComment $id]
    bind $win.content.ctext <Return>        [list IndentOnReturn $id]
    bind $win.content.ctext <Tab>           [list IndentBuffer $id 1]
    bind $win.content.ctext <ISO_Left_Tab>  [list IndentBuffer $id -1]
    bind $win.content.ctext <Shift-Tab>     [list IndentBuffer $id -1]
    bind $win.content.ctext <Escape>        [list HideFindBar $id]
    bind $win.content.ctext <Control-Tab>   {CycleBuffer 1; break}
    bind $win.content.ctext <Control-Shift-Tab> {CycleBuffer -1; break}

    if {$Buffers($id,content) ne ""} {
        $win.content.ctext fastinsert 1.0 $Buffers($id,content)
        $win.content.ctext edit modified 0
    }
    ApplySyntaxForBuffer $id

    focus $win.content.ctext
    ActivateWindow $id
    UpdateLineCounter $id
}

# --- Window chrome --------------------------------------------------------

# Status bar: cursor position, line ratio, and language id.
proc UpdateLineCounter {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    set ctextWidget $win.content.ctext

    set insertIdx   [$ctextWidget index insert]
    set currentLine [lindex [split $insertIdx "."] 0]
    set currentCol  [expr {[lindex [split $insertIdx "."] 1] + 1}]
    set totalLines  [lindex [split [$ctextWidget index end-1c] "."] 0]

    $win.statusbar.lines configure -text "Ln $currentLine, Col $currentCol"
    $win.statusbar.info  configure -text "$currentLine:$totalLines"

    set lang ""
    if {[info exists Buffers($id,lang)] && $Buffers($id,lang) ne ""} {
        set lang $Buffers($id,lang)
    }
    $win.statusbar.lang configure -text $lang
}

# Collapse the window to a title bar, or restore content and height.
proc MinimizeWindow {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)

    if {[info exists Buffers($id,visible)] && $Buffers($id,visible)} {
        set Buffers($id,rest_h) [winfo height $win]
        grid forget $win.content
        grid forget $win.statusbar
        grid forget $win.findbar
        place forget $win.resize
        place $win -height 28
        set Buffers($id,visible) 0
    } else {
        grid $win.content   -row 1 -column 0 -sticky nsew
        grid $win.statusbar -row 2 -column 0 -sticky ew
        if {[info exists Buffers($id,findbar)] && $Buffers($id,findbar)} {
            grid $win.findbar -row 3 -column 0 -sticky ew
        }
        set h 350
        if {[info exists Buffers($id,rest_h)]} {
            set h $Buffers($id,rest_h)
        }
        place $win -height $h
        set Buffers($id,visible) 1
        PlaceResizeHandle $id
    }
    UpdateBufferList
}

# Raise the buffer window.
proc RaiseWindow {id} {
    global ZIndex Buffers
    incr ZIndex
    if {[SafeWindowExists $id]} {
        raise $Buffers($id,window)
        PlaceResizeHandle $id
    }
}

# Raise the window and mark the buffer active (sidebar, Save, Find).
proc ActivateWindow {id} {
    RaiseWindow $id
    SetActiveBuffer $id
}

# Remember the active buffer. Does not steal focus from the findbar.
proc SetActiveBuffer {id} {
    global ActiveBufferId
    set ActiveBufferId $id
    UpdateBufferList
    UpdateStatus
}

# <<Modified>> handler: dirty flag, title asterisk, sidebar, cursor.
proc OnTextChange {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    set Buffers($id,modified) [$win.content.ctext edit modified]

    UpdateWindowTitle $id
    UpdateBufferList
    UpdateLineCounter $id
}

# Titlebar text: file name plus " *" when dirty.
proc UpdateWindowTitle {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    set title "$Buffers($id,name)"
    if {$Buffers($id,modified)} { append title " *" }
    $win.titlebar.label configure -text $title
}

# Rebuild the sidebar listbox in AllBufferIds order.
proc UpdateBufferList {} {
    global Buffers ActiveBufferId SidebarList Config

    $SidebarList delete 0 end

    foreach id [AllBufferIds] {
        set label "$Buffers($id,name)"
        if {$Buffers($id,modified)} { append label " *" }
        if {[info exists Buffers($id,visible)] && !$Buffers($id,visible)} {
            append label " (min)"
        }
        $SidebarList insert end $label

        if {$id == $ActiveBufferId} {
            $SidebarList itemconfigure end -background $Config(sel_bg) -foreground $Config(sel_fg)
        } else {
            $SidebarList itemconfigure end -background $Config(sidebar_bg) -foreground $Config(list_fg)
        }
    }
}

# Activate by listbox row index (names may collide).
proc ActivateBufferByIndex {idx} {
    global Buffers
    set ids [AllBufferIds]
    if {$idx < 0 || $idx >= [llength $ids]} return
    set id [lindex $ids $idx]
    ActivateWindow $id
    if {![SafeWindowExists $id]} return
    set win $Buffers($id,window)
    if {[info exists Buffers($id,findbar)] && $Buffers($id,findbar)} {
        focus $win.findbar.find
    } else {
        focus $win.content.ctext
    }
}

# Walk the buffer list; dir is +1 or -1.
proc CycleBuffer {dir} {
    global ActiveBufferId
    set ids [AllBufferIds]
    set n [llength $ids]
    if {$n == 0} return
    set i [lsearch -exact $ids $ActiveBufferId]
    if {$i < 0} { set i 0 }
    set i [expr {($i + $dir) % $n}]
    ActivateBufferByIndex $i
}

# Toolbar status: path or buffer name.
proc UpdateStatus {} {
    global ActiveBufferId Buffers StatusLabel
    if {$ActiveBufferId eq "" || ![info exists Buffers($ActiveBufferId,name)]} {
        $StatusLabel configure -text "Ready"
    } else {
        set path $Buffers($ActiveBufferId,path)
        if {$path eq ""} {
            $StatusLabel configure -text $Buffers($ActiveBufferId,name)
        } else {
            $StatusLabel configure -text $path
        }
    }
}

# --- Drag and resize ------------------------------------------------------

# Record the grab point for titlebar dragging.
proc StartDrag {widget x y id} {
    global DragStart DragWin
    set DragWin [winfo parent $widget]
    if {[winfo class $widget] eq "Label"} {
        set DragWin [winfo parent $DragWin]
    }
    set DragStart(x) $x
    set DragStart(y) $y
    ActivateWindow $id
}

# Move the window by the mouse delta; Y stays >= 1.
proc OnDrag {widget x y id} {
    global DragStart DragWin Buffers
    if {![info exists DragWin]} return
    if {![winfo exists $DragWin]} return

    set dx [expr {$x - $DragStart(x)}]
    set dy [expr {$y - $DragStart(y)}]
    set newX [expr {[winfo x $DragWin] + $dx}]
    set newY [expr {max(1, [winfo y $DragWin] + $dy)}]
    place $DragWin -x $newX -y $newY
    set DragStart(x) $x
    set DragStart(y) $y
    set Buffers($id,maximized) 0
}

# Snapshot size when the resize grip is pressed.
proc StartResize {widget x y id} {
    global ResizeStart ResizeWin
    set ResizeWin [winfo parent $widget]
    set ResizeStart(x) $x
    set ResizeStart(y) $y
    set ResizeStart(w) [winfo width $ResizeWin]
    set ResizeStart(h) [winfo height $ResizeWin]
    ActivateWindow $id
}

# Resize; minimum 200×150.
proc OnResize {widget x y id} {
    global ResizeStart ResizeWin Buffers
    if {![info exists ResizeWin]} return
    if {![winfo exists $ResizeWin]} return

    set dx [expr {$x - $ResizeStart(x)}]
    set dy [expr {$y - $ResizeStart(y)}]

    set newW [expr {max(200, $ResizeStart(w) + $dx)}]
    set newH [expr {max(150, $ResizeStart(h) + $dy)}]
    place $ResizeWin -width $newW -height $newH
    set Buffers($id,maximized) 0
}

# Fill the desktop (with gutter) or restore the saved geometry.
proc ToggleMaximize {id} {
    global Buffers
    if {![SafeWindowExists $id]} return
    if {![info exists Buffers($id,visible)] || !$Buffers($id,visible)} return

    set win $Buffers($id,window)

    if {[info exists Buffers($id,maximized)] && $Buffers($id,maximized)} {
        set x 20
        set y 20
        set w 500
        set h 350
        if {[info exists Buffers($id,rest_x)]} {
            set x $Buffers($id,rest_x)
            set y $Buffers($id,rest_y)
            set w $Buffers($id,rest_w)
            set h $Buffers($id,rest_h)
        }
        place $win -x $x -y $y -width $w -height $h
        set Buffers($id,maximized) 0
    } else {
        set Buffers($id,rest_x) [winfo x $win]
        set Buffers($id,rest_y) [winfo y $win]
        set Buffers($id,rest_w) [winfo width $win]
        set Buffers($id,rest_h) [winfo height $win]
        lassign [MaximizedGeom] mx my mw mh
        place $win -x $mx -y $my -width $mw -height $mh
        set Buffers($id,maximized) 1
    }
    PlaceResizeHandle $id
}

# --- Files ----------------------------------------------------------------

# Open-file dialog; an already-open path is only activated.
proc OpenFile {} {
    global Buffers

    set types {
        {{Tcl Files}   {.tcl .tk}}
        {{C Files}     {.c .h .cpp .cc}}
        {{Shell Files} {.sh .bash}}
        {{Text Files}  {.txt}}
        {{All Files}   *}
    }

    set filename [tk_getOpenFile -filetypes $types -title "Open File"]
    if {$filename eq ""} return

    foreach key [array names Buffers *,path] {
        if {$Buffers($key) eq $filename} {
            set id [lindex [split $key ","] 0]
            ActivateWindow $id
            return
        }
    }

    if {[catch {
        set fh [open $filename r]
        fconfigure $fh -encoding utf-8
        set content [read $fh]
        close $fh
    } err]} {
        tk_messageBox -icon error -message "Cannot open file: $err"
        return
    }

    CreateBuffer [file tail $filename] $filename $content
}

# Write the buffer to disk; path-less buffers go through Save As.
proc SaveBuffer {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    if {$Buffers($id,path) eq ""} {
        SaveAsBuffer $id
        return
    }

    set win $Buffers($id,window)
    set content [$win.content.ctext get 1.0 end-1c]

    if {[catch {
        set fh [open $Buffers($id,path) w]
        fconfigure $fh -encoding utf-8
        puts -nonewline $fh $content
        close $fh
    } err]} {
        tk_messageBox -icon error -message "Cannot save file: $err"
        return
    }

    set Buffers($id,content)  $content
    set Buffers($id,modified) 0

    $win.content.ctext edit modified 0
    ApplySyntaxForBuffer $id
    UpdateWindowTitle $id
    UpdateBufferList
    UpdateStatus
}

# Save-As dialog, then SaveBuffer.
proc SaveAsBuffer {id} {
    global Buffers
    if {![info exists Buffers($id,id)]} return

    set types {
        {{Tcl Files}   {.tcl}}
        {{C Files}     {.c .h}}
        {{Shell Files} {.sh}}
        {{Text Files}  {.txt}}
        {{All Files}   *}
    }

    set filename [tk_getSaveFile -filetypes $types -title "Save As"]
    if {$filename eq ""} return

    set Buffers($id,path) $filename
    set Buffers($id,name) [file tail $filename]

    SaveBuffer $id
}

# Close the buffer. A cancelled Save As or write error keeps the window.
proc CloseBuffer {id} {
    global Buffers ActiveBufferId

    if {[info exists Buffers($id,modified)] && $Buffers($id,modified)} {
        set answer [tk_messageBox -icon warning -type yesnocancel \
            -message "Save changes to $Buffers($id,name)?"]
        if {$answer eq "yes"} {
            SaveBuffer $id
            if {[info exists Buffers($id,modified)] && $Buffers($id,modified)} {
                return
            }
        } elseif {$answer eq "cancel"} {
            return
        }
    }

    if {[SafeWindowExists $id]} {
        destroy $Buffers($id,window)
    }

    foreach key [array names Buffers $id,*] {
        unset Buffers($key)
    }

    set ids [AllBufferIds]
    if {[llength $ids] > 0} {
        ActivateBufferByIndex 0
    } else {
        set ActiveBufferId ""
        UpdateStatus
    }

    UpdateBufferList
}

# --- Main window ----------------------------------------------------------

# Show or hide the sidebar and relayout maximized windows.
proc ToggleSidebar {} {
    global SidebarVisible

    set SidebarVisible [expr {!$SidebarVisible}]
    PlaceDesktop
    update idletasks
    RelayoutMaximized
}

# Stretch maximized buffers to the current desktop size (with gutter).
proc RelayoutMaximized {} {
    global Buffers Desktop
    if {![winfo exists $Desktop]} return

    lassign [MaximizedGeom] mx my mw mh
    foreach key [array names Buffers *,maximized] {
        if {$Buffers($key)} {
            set id [lindex [split $key ","] 0]
            if {[SafeWindowExists $id]} {
                place $Buffers($id,window) -x $mx -y $my -width $mw -height $mh
                PlaceResizeHandle $id
            }
        }
    }
}

# Toolbar, sidebar, desktop, and global hotkeys.
proc BuildUI {} {
    global Config Desktop SidebarList StatusLabel Layout

    set scriptDir [file dirname [file normalize [info script]]]
    set iconPath [file join $scriptDir "img/icon.png"]
    if {[file exists $iconPath]} {
        image create photo miedIcon -file $iconPath
        catch {wm iconphoto . -default miedIcon}
    }

    catch {wm title . "Mied"}
    catch {wm geometry . 1200x800}
    . configure -bg $Config(bg)

    # Same 1px $Config(border) rim as buffer windows.
    frame .toolbar -bg $Config(border) -bd 1 -relief flat -height $Layout(toolbar_h)
    pack .toolbar -fill x -side top
    frame .toolbar.inner -bg $Config(toolbar_bg)
    pack .toolbar.inner -fill both -expand 1

    set toolbarButtons {
        {new     40 "New"      NewBuffer}
        {open    40 "Open"     OpenFile}
        {save    40 "Save"     SaveActiveBuffer}
        {saveas  60 "Save As"  SaveAsActiveBuffer}
        {sidebar 60 "Buffers"  ToggleSidebar}
        {about   40 "About"    ShowAbout}
    }
    foreach btn $toolbarButtons {
        lassign $btn bname bwidth btext bcmd
        MakeToolbarButton $bname $bwidth $btext $bcmd
    }

    frame .toolbar.inner.spacer -bg $Config(toolbar_bg)
    pack .toolbar.inner.spacer -side left -expand 1 -fill x

    label .toolbar.inner.status -text "Ready" -fg $Config(status_fg) \
        -bg $Config(toolbar_bg) -font $Config(ui_font)
    pack .toolbar.inner.status -side right -padx 10
    set StatusLabel .toolbar.inner.status

    frame .sidebar -bg $Config(border) -bd 1 -relief flat -width $Layout(sidebar_w)

    label .sidebar.header -text "Buffers" -fg $Config(header_fg) \
        -bg $Config(sidebar_bg) -font $Config(ui_font)
    place .sidebar.header -x 0 -y 0 -relwidth 1 -height 24

    listbox .sidebar.list -bg $Config(sidebar_bg) -fg $Config(list_fg) \
        -font $Config(ui_font) -bd 0 -highlightthickness 0 \
        -selectbackground $Config(sel_bg) -selectforeground $Config(sel_fg) \
        -activestyle none -exportselection 0
    place .sidebar.list -x 0 -y 24 -relwidth 1 -relheight 1 -height -24
    set SidebarList .sidebar.list

    bind .sidebar.list <Button-1> {
        set idx [%W nearest %y]
        set bbox [%W bbox $idx]
        if {$bbox ne {}} {
            lassign $bbox bx by bw bh
            if {%y >= $by && %y < $by + $bh} {
                ActivateBufferByIndex $idx
            }
        }
    }
    bind .sidebar.list <Double-Button-1> {
        set idx [%W nearest %y]
        set bbox [%W bbox $idx]
        if {$bbox ne {}} {
            lassign $bbox bx by bw bh
            if {%y >= $by && %y < $by + $bh} {
                ActivateBufferByIndex $idx
                global ActiveBufferId
                if {$ActiveBufferId ne ""} {
                    ToggleMaximize $ActiveBufferId
                }
            }
        }
    }

    frame .desktop -bg $Config(bg)
    set Desktop .desktop
    PlaceDesktop

    bind .desktop <Configure> RelayoutMaximized

    bind . <Control-n> NewBuffer
    bind . <Control-o> OpenFile
    bind . <Control-s> SaveActiveBuffer
    bind . <Control-b> ToggleSidebar
    bind . <Control-f> OpenFindDialog
    bind . <Control-Tab> {CycleBuffer 1}
    bind . <Control-Shift-Tab> {CycleBuffer -1}
}

# Save the active buffer (toolbar / Ctrl+S).
proc SaveActiveBuffer {} {
    global ActiveBufferId
    if {$ActiveBufferId ne ""} {
        SaveBuffer $ActiveBufferId
    }
}

# Save As for the active buffer.
proc SaveAsActiveBuffer {} {
    global ActiveBufferId
    if {$ActiveBufferId ne ""} {
        SaveAsBuffer $ActiveBufferId
    }
}

# Paint the Aa button: filled accent when case-sensitive is on.
proc StyleCaseButton {path} {
    global FindCaseSensitive Config
    if {![winfo exists $path]} return

    if {$FindCaseSensitive} {
        set bg $Config(accent)
        set fg $Config(sel_fg)
        set hoverBg $Config(accent)
        set hoverFg $Config(sel_fg)
    } else {
        set bg $Config(toolbar_bg)
        set fg $Config(fg)
        set hoverBg $Config(btn_hover_bg)
        set hoverFg $Config(hover_fg)
    }

    $path configure -bg $bg
    $path itemconfigure bg -fill $bg
    $path itemconfigure label -fill $fg

    $path bind hit <Enter> [list apply {{path hoverBg hoverFg} {
        $path configure -bg $hoverBg
        $path itemconfigure bg -fill $hoverBg
        $path itemconfigure label -fill $hoverFg
    }} $path $hoverBg $hoverFg]
    $path bind hit <Leave> [list apply {{path bg fg} {
        $path configure -bg $bg
        $path itemconfigure bg -fill $bg
        $path itemconfigure label -fill $fg
    }} $path $bg $fg]
}

# Toggle case-sensitive search and refresh every Aa button.
proc ToggleFindCase {} {
    global FindCaseSensitive Buffers
    set FindCaseSensitive [expr {!$FindCaseSensitive}]
    foreach id [AllBufferIds] {
        if {[SafeWindowExists $id]} {
            StyleCaseButton $Buffers($id,window).findbar.btn_case
        }
    }
}

# --- Find / replace -------------------------------------------------------

# Ctrl+F: show the find bar on the active window.
proc OpenFindDialog {} {
    global ActiveBufferId
    if {$ActiveBufferId eq ""} return
    ShowFindBar $ActiveBufferId
}

# Show the find bar and focus the search field.
proc ShowFindBar {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    if {[info exists Buffers($id,visible)] && !$Buffers($id,visible)} {
        MinimizeWindow $id
    }

    set win $Buffers($id,window)
    set Buffers($id,findbar) 1
    grid $win.findbar -row 3 -column 0 -sticky ew
    PlaceResizeHandle $id
    focus $win.findbar.find
}

# Hide the find bar and clear match tags.
proc HideFindBar {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    $win.content.ctext tag remove found 1.0 end
    grid forget $win.findbar
    set Buffers($id,findbar) 0
    PlaceResizeHandle $id
    focus $win.content.ctext
}

# Search from startIdx; wrap to start/end on miss. Returns {index length} or {{} 0}.
proc FindInBuffer {id direction startIdx} {
    global FindPattern FindCaseSensitive Buffers
    if {![SafeWindowExists $id]} { return [list "" 0] }

    set ctext $Buffers($id,window).content.ctext
    if {$FindPattern eq ""} { return [list "" 0] }

    set length 0
    set switches [list -count length -$direction]
    if {!$FindCaseSensitive} { lappend switches -nocase }

    set idx [$ctext search {*}$switches -- $FindPattern $startIdx]
    if {$idx eq ""} {
        if {$direction eq "forwards"} {
            set idx [$ctext search {*}$switches -- $FindPattern 1.0]
        } else {
            set idx [$ctext search {*}$switches -- $FindPattern end]
        }
    }

    if {$idx eq ""} {
        return [list "" 0]
    }
    return [list $idx $length]
}

# Next match forward; select it and tag found.
proc FindNextInBuffer {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set ctext $Buffers($id,window).content.ctext
    $ctext tag remove found 1.0 end

    if {[$ctext tag ranges sel] ne ""} {
        set startIdx [$ctext index sel.last]
    } else {
        set startIdx [$ctext index "insert +1 chars"]
    }

    lassign [FindInBuffer $id forwards $startIdx] idx len
    if {$idx ne ""} {
        $ctext mark set insert $idx
        $ctext see $idx
        $ctext tag remove sel 1.0 end
        set endIdx [$ctext index "$idx + $len chars"]
        $ctext tag add sel $idx $endIdx
        $ctext tag add found $idx $endIdx
    }
}

# Previous match backward.
proc FindPrevInBuffer {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set ctext $Buffers($id,window).content.ctext
    $ctext tag remove found 1.0 end

    if {[$ctext tag ranges sel] ne ""} {
        set startIdx [$ctext index "sel.first -1 chars"]
    } else {
        set startIdx [$ctext index "insert -1 chars"]
    }

    lassign [FindInBuffer $id backwards $startIdx] idx len
    if {$idx ne ""} {
        $ctext mark set insert $idx
        $ctext see $idx
        $ctext tag remove sel 1.0 end
        set endIdx [$ctext index "$idx + $len chars"]
        $ctext tag add sel $idx $endIdx
        $ctext tag add found $idx $endIdx
    }
}

# Replace the current selection if it is a match, then find the next one.
proc ReplaceInBuffer {id} {
    global FindPattern ReplacePattern FindCaseSensitive Buffers
    if {![SafeWindowExists $id]} return

    set ctext $Buffers($id,window).content.ctext
    if {$FindPattern eq ""} return

    if {[$ctext tag ranges sel] eq ""} {
        FindNextInBuffer $id
        return
    }

    set selStart [$ctext index sel.first]
    set selEnd   [$ctext index sel.last]
    set selected [$ctext get $selStart $selEnd]
    set pattern $FindPattern
    if {!$FindCaseSensitive} {
        set selected [string tolower $selected]
        set pattern  [string tolower $pattern]
    }

    if {$selected ne $pattern} {
        FindNextInBuffer $id
        return
    }

    $ctext delete $selStart $selEnd
    $ctext insert $selStart $ReplacePattern
    $ctext highlight $selStart "$selStart + [string length $ReplacePattern] chars"
    FindNextInBuffer $id
}

# Replace every occurrence; stop after 10000 as a safety cap.
proc ReplaceAllInBuffer {id} {
    global FindPattern FindCaseSensitive Buffers
    if {![SafeWindowExists $id]} return

    set ctext $Buffers($id,window).content.ctext
    if {$FindPattern eq ""} return

    set switches [list -count length -forwards]
    if {!$FindCaseSensitive} { lappend switches -nocase }

    set count 0
    set idx 1.0

    while {1} {
        set found [$ctext search {*}$switches -- $FindPattern $idx]
        if {$found eq ""} break
        $ctext delete $found [$ctext index "$found + $length chars"]
        $ctext insert $found $::ReplacePattern
        set idx [$ctext index "$found + [string length $::ReplacePattern] chars"]
        incr count
        if {$count > 10000} break
    }

    if {$count > 0} {
        $ctext tag remove sel 1.0 end
        $ctext highlight 1.0 end
    }
}

# --- Editing helpers ------------------------------------------------------

# Select the line that contains the insert cursor (Ctrl+L).
proc SelectCurrentLine {id} {
    global Buffers
    if {![SafeWindowExists $id]} return
    set ctext $Buffers($id,window).content.ctext
    $ctext tag remove sel 1.0 end
    $ctext tag add sel "insert linestart" "insert lineend +1c"
}

# Copy leading whitespace onto the new line after Return.
proc IndentOnReturn {id} {
    global Buffers
    if {![SafeWindowExists $id]} { return -code break }
    set ctext $Buffers($id,window).content.ctext
    set prefix ""
    regexp {^[[:space:]]*} [$ctext get "insert linestart" insert] prefix
    $ctext insert insert "\n$prefix"
    $ctext see insert
    return -code break
}

# Tab / Shift-Tab: indent or outdent the selected lines (or the current line).
proc IndentBuffer {id delta} {
    global Buffers
    if {![SafeWindowExists $id]} { return -code break }
    set ctext $Buffers($id,window).content.ctext

    if {[$ctext tag ranges sel] eq ""} {
        if {$delta > 0} {
            $ctext insert insert "\t"
            return -code break
        }
        set first [$ctext index "insert linestart"]
        set last  [$ctext index "insert lineend"]
    } else {
        set first [$ctext index "sel.first linestart"]
        set last  [$ctext index "sel.last lineend"]
    }

    set startLine [lindex [split $first "."] 0]
    set endLine   [lindex [split $last "."] 0]
    for {set n $startLine} {$n <= $endLine} {incr n} {
        if {$delta > 0} {
            $ctext insert $n.0 "\t"
        } else {
            set ch [$ctext get $n.0 "$n.0 +1c"]
            if {$ch eq "\t"} {
                $ctext delete $n.0 "$n.0 +1c"
            } elseif {$ch eq " "} {
                set i 0
                while {$i < 4 && [$ctext get "$n.0 +$i c"] eq " "} { incr i }
                if {$i > 0} { $ctext delete $n.0 "$n.0 +$i c" }
            }
        }
    }
    return -code break
}

# Toggle a language-appropriate comment on each selected (or current) line.
proc ToggleComment {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set ctext $Buffers($id,window).content.ctext
    set lang ""
    if {[info exists Buffers($id,lang)]} { set lang $Buffers($id,lang) }
    set prefix [CommentPrefix $lang]
    set plen [string length $prefix]

    if {[$ctext tag ranges sel] eq ""} {
        set first [$ctext index "insert linestart"]
        set last  [$ctext index "insert lineend"]
    } else {
        set first [$ctext index "sel.first linestart"]
        set last  [$ctext index "sel.last lineend"]
    }

    set startLine [lindex [split $first "."] 0]
    set endLine   [lindex [split $last "."] 0]

    set allCommented 1
    for {set n $startLine} {$n <= $endLine} {incr n} {
        set line [$ctext get $n.0 "$n.0 lineend"]
        if {[string trim $line] eq ""} continue
        set trimmed [string trimleft $line]
        if {![string equal -length $plen $trimmed $prefix]} {
            set allCommented 0
            break
        }
    }

    for {set n $startLine} {$n <= $endLine} {incr n} {
        set line [$ctext get $n.0 "$n.0 lineend"]
        if {[string trim $line] eq ""} continue
        if {$allCommented} {
            set idx [string first $prefix $line]
            if {$idx >= 0} {
                $ctext delete $n.$idx "$n.$idx + $plen c"
                if {[$ctext get $n.$idx] eq " "} {
                    $ctext delete $n.$idx "$n.$idx +1c"
                }
            }
        } else {
            regexp -indices {^[[:space:]]*} $line span
            set col [lindex $span 1]
            incr col
            $ctext insert $n.$col "$prefix "
        }
    }

    # Place cursor at start of first modified line
    $ctext mark set insert "$startLine.0"
    $ctext see insert

    return -code break
}

# --- About ----------------------------------------------------------------

proc ShowAbout {} {
    global Mied Config

    if {[winfo exists .about]} {
        raise .about
        return
    }

    set win [toplevel .about -bg $Config(bg)]
    wm title $win "About Mied"
    wm geometry $win 380x280
    wm resizable $win 0 0
    wm transient $win .
    wm protocol $win WM_DELETE_WINDOW [list destroy $win]

    frame $win.body -bg $Config(bg)
    pack $win.body -fill both -expand 1 -padx 20 -pady 24

    catch {
        label $win.body.icon -image miedIcon -bg $Config(bg)
        pack $win.body.icon -pady {0 12}
    }

    label $win.body.title -text "Mied" \
        -bg $Config(bg) -fg $Config(title_fg) \
        -font {"Fira Code" 18 bold}
    pack $win.body.title

    label $win.body.ver -text "Version $Mied(version)" \
        -bg $Config(bg) -fg $Config(fg) \
        -font {"Fira Code" 10}
    pack $win.body.ver -pady {4 0}

    frame $win.body.spacer -bg $Config(bg) -height 30
    pack $win.body.spacer -fill x -expand 1

    label $win.body.copy -text "$Mied(authors)\n$Mied(license)" \
        -bg $Config(bg) -fg $Config(status_fg) \
        -font $Config(ui_font) -justify center
    pack $win.body.copy -pady {0 8}

    focus $win
}

# --- Start ----------------------------------------------------------------

BuildUI
