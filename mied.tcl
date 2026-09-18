#!/usr/bin/env tclsh
#
# Mied - a small editor on Tcl/Tk.
#
# Usage:
#     wish mied.tcl [-config <config-file>] [file ...]
#
# Options:
#     -config <file>   Load the editor configuration.
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
#              - version 0.4.0 added "syntax_highlight" to config
#                              added info about about build binary
#                              fixing selecting file in treeview buffer
#                              language support moved to langs/*.lang
#                              added PHP syntax support
#     2026-09-12 version 0.3.0 added -config option to load a config file
#                              fixing ui size with bigger ui font
#                              added treeview buffer
#     2026-09-01 version 0.2.0 added About window
#                              added Markdown, Go, Lua syntax highlight
#                              added the ability to open files via argv
#     2026-08-28 version 0.1.1 fixing PlaceResizeHandle with MinimizeWindow
#                              fixing ToggleMaximize with MinimizeWindow
#     2026-08-22 version 0.1

package require Tk
package require ctext

set Mied(version) "0.4.0"
set Mied(authors) "Daniil Arkhangelsky (Kiky Tokamuro)"
set Mied(license) "MIT License, 2026"

# --- Application state ----------------------------------------------------

array set Buffers {}          ;# per-buffer fields: id,name,path,content,...
set ActiveBufferId ""         ;# target of Save / Find / highlighting extras
set ZIndex 100                ;# stacking counter used with raise
set SidebarVisible 0

set FindPattern ""
set ReplacePattern ""
set FindCaseSensitive 0

# --- Layout ---------------------------------------------------------------

set Layout(sidebar_w) 180
set Layout(gap)       2       ;# gutter between sidebar and desktop

# Size component of a font descriptor ({family size ?style?}). 9 is the
# default ui size and the reference for every scaled chrome metric.
proc FontSize {font} {
    set size [lindex $font 1]
    if {[string is integer -strict $size]} {
        return [expr {abs($size)}]
    }
    return 9
}

# Derive bar, button, and padding sizes from Config(ui_font) so the chrome
# grows with the font instead of clipping labels inside fixed-size widgets.
# At the default ui size these match the original fixed layout.
proc ComputeLayout {} {
    global Config Layout

    set scale [expr {double([FontSize $Config(ui_font)]) / 9.0}]
    if {$scale < 1.0} { set scale 1.0 }
    set Layout(padx)     [expr {max(4, int(round(4 * $scale)))}]
    set Layout(pady)     [expr {max(3, int(round(3 * $scale)))}]
    set Layout(find_pad) [expr {max(2, int(round(2 * $scale)))}]

    set line   [font metrics $Config(ui_font) -linespace]
    set minBtn [expr {$line + 2}]

    set Layout(btn_h)      [expr {max(int(round(24 * $scale)), $minBtn)}]
    set Layout(findbtn_h)  [expr {max(int(round(22 * $scale)), $minBtn)}]
    set Layout(titlebtn_h) [expr {max(int(round(20 * $scale)), $minBtn)}]

    set Layout(toolbar_h)   [expr {$Layout(btn_h) + 2 * $Layout(pady) + 2}]
    set Layout(titlebar_h)  [expr {max(int(round(26 * $scale)), $Layout(titlebtn_h) + 2 * $Layout(pady))}]
    set Layout(findbar_h)   [expr {$Layout(findbtn_h) + 2 * $Layout(find_pad)}]
    set Layout(statusbar_h) [expr {max(int(round(22 * $scale)), $line + 2 * $Layout(pady))}]
    set Layout(header_h)    [expr {max(int(round(24 * $scale)), $line + 2 * $Layout(pady))}]
}

# --- Config ----------------------------------------------------------------

# Built-in defaults. A user config file (-config) may override any of them.
proc LoadDefaultConfig {} {
    global Config

    set Config(accent)       "#5d7e73"
    set Config(bg)           "#e8e8e8"
    set Config(fg)           "#666666"
    set Config(toolbar_bg)   "#c8c8c8"
    set Config(sidebar_bg)   "#c8c8c8"
    set Config(window_bg)    "#ffffff"
    set Config(titlebar_bg)  "#c8c8c8"
    set Config(border)       "#aaaaaa"
    set Config(font)         {"Fira Code" 10}
    set Config(font_bold)    {"Fira Code" 10 bold}
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

    # File tree buffers start with dot entries hidden; Ctrl+H toggles it.
    set Config(tree_show_hidden) 0

    # Syntax highlighting is on by default; 0 renders buffers as plain text.
    set Config(syntax_highlight) 1

    # Monochrome highlight
    set Config(hl_keyword)   "#222222"
    set Config(hl_comment)   "#9a9a9a"
    set Config(hl_string)    "#555555"
    set Config(hl_number)    "#333333"
    set Config(hl_punct)     "#777777"
    set Config(hl_preproc)   "#444444"
}

# Source a user config file over the defaults. The file is plain Tcl and can
# set any Config(...) key; keys it does not set keep their default values.
proc LoadConfigFile {path} {
    global Config

    if {![file exists $path]} {
        puts stderr "mied: config file '$path' not found, using default config"
        return 0
    }
    if {![file isfile $path] || ![file readable $path]} {
        puts stderr "mied: cannot read config file '$path', using default config"
        return 0
    }

    if {[catch {source $path} err]} {
        puts stderr "mied: error in config file '$path': $err"
        puts stderr "mied: falling back to default config"
        array unset Config
        LoadDefaultConfig
        return 0
    }

    return 1
}

# --- Helpers --------------------------------------------------------------

# True if the buffer window for id is still mapped.
proc SafeWindowExists {id} {
    global Buffers
    return [expr {[info exists Buffers($id,window)] && [winfo exists $Buffers($id,window)]}]
}

# True when the buffer is an editable text document (not a file tree).
proc IsEditor {id} {
    global Buffers
    return [expr {[info exists Buffers($id,kind)] && $Buffers($id,kind) eq "editor"}]
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

# Distance from the window bottom to the resize grip: above the status bar
# and, when the find bar is open, above that as well. Bar heights are measured
# from the widgets, since the bars size themselves from their contents.
proc ResizeHandleOffset {id} {
    global Buffers

    set win $Buffers($id,window)
    set yOff [winfo reqheight $win.statusbar]
    if {[info exists Buffers($id,findbar)] && $Buffers($id,findbar) \
            && [winfo exists $win.findbar]} {
        incr yOff [winfo reqheight $win.findbar]
    }
    return [expr {-$yOff}]
}

# Pins the resize grip above the status bar (and findbar, if shown).
proc PlaceResizeHandle {id} {
	global Buffers
	if {![SafeWindowExists $id]} return
	if {![info exists Buffers($id,visible)] || !$Buffers($id,visible)} return

    set win $Buffers($id,window)
    set yOff [ResizeHandleOffset $id]
    place $win.resize -relx 1.0 -rely 1.0 -anchor se -y $yOff
    raise $win.resize
}

# Flat canvas button. Uses grid when -row/-column is present, otherwise pack.
# width/height are minimums: the button grows to fit its label, so toolbar and
# find bar text stays readable whatever Config(ui_font) is set to.
proc MakeFlatButton {parent name width height text font bg fg hover_bg hover_fg cmd geomopts} {
    global Layout

    set width  [expr {max($width, [font measure $font $text] + 2 * $Layout(padx))}]
    set height [expr {max($height, [font metrics $font -linespace] + 2)}]

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

# Toolbar button, 24px high at the default font size.
proc MakeToolbarButton {name width text cmd} {
    global Config Layout
    MakeFlatButton .toolbar.inner $name $width $Layout(btn_h) $text \
        $Config(ui_font) $Config(toolbar_bg) $Config(fg) \
        $Config(btn_hover_bg) $Config(hover_fg) $cmd \
        [list -side left -padx 2 -pady $Layout(pady)]
}

# --- Languages ------------------------------------------------------------

# Colour role -> Config key. Language files name a role instead of a colour,
# so a theme keeps control over what that role looks like.
array set LangColorKey {
    keyword hl_keyword
    comment hl_comment
    string  hl_string
    number  hl_number
    punct   hl_punct
    preproc hl_preproc
}

# Language registry: Langs(<name>,<field>) holds what each file declared plus
# the classes it added, in declaration order. LangOrder is the load order,
# which is what breaks ties between languages claiming the same file, and
# LangExt maps an extension to a language.
array set Langs {}
array set LangExt {}
set LangOrder {}
set LangCurrent ""

# Language <name> {extensions {...} ?shebang {...}? ?line_comment <prefix>?}
# extensions   file extensions the language claims, e.g. {.go}
# shebang      regexps matched against a "#!" first line, e.g. {bash dash}
# line_comment prefix Ctrl+/ adds, e.g. //
proc Language {name opts} {
    global Langs LangOrder LangCurrent

    if {$name eq ""} {
        error "Language: a language needs a name"
    }

    set fields {extensions {} shebang {} line_comment {}}
    foreach key [dict keys $opts] {
        if {[lsearch -exact {extensions shebang line_comment} $key] < 0} {
            error "Language $name: unknown option '$key'"
        }
        if {$key eq "shebang"} {
            foreach pattern [dict get $opts $key] {
                if {[catch {regexp -- $pattern "#!"} err]} {
                    error "Language $name: bad shebang pattern '$pattern': $err"
                }
            }
        }
        dict set fields $key [dict get $opts $key]
    }

    set LangCurrent $name
    if {[lsearch -exact $LangOrder $name] < 0} {
        lappend LangOrder $name
    }
    foreach {key value} $fields {
        set Langs($name,$key) $value
    }
    set Langs($name,classes) {}
}

# Whole-word class, e.g. keywords or builtins.
proc HighlightClass {tag role words} {
    AddLanguageClass class $tag $role $words
}

# Regexp class, e.g. strings, comments, or numbers.
proc HighlightRegexp {tag role re} {
    AddLanguageClass regexp $tag $role $re
}

# Class for a set of punctuation characters, e.g. {()[]{};}.
proc HighlightChars {tag role chars} {
    AddLanguageClass chars $tag $role $chars
}

# Class that starts at a character, e.g. "$" for variables.
proc HighlightChar {tag role char} {
    AddLanguageClass char $tag $role $char
}

# Records one highlight class for the language of the last Language call.
proc AddLanguageClass {kind tag role spec} {
    global Langs LangCurrent LangColorKey

    if {$LangCurrent eq ""} {
        error "$kind $tag: declare Language before any highlight class"
    }
    if {![info exists LangColorKey($role)]} {
        error "$kind $tag: unknown colour role '$role'"
    }

    lappend Langs($LangCurrent,classes) [list $kind $tag $role $spec]
}

# Directory holding the language files.
proc LanguageDir {} {
    return [file join [file dirname [file normalize [info script]]] langs]
}

# Read every *.lang in dir, in a fixed order so overrides are predictable.
# Languages are optional: without them every buffer renders as plain text.
proc LoadLanguages {dir} {
    global LangOrder

    if {![file isdirectory $dir]} {
        puts stderr "mied: language directory '$dir' not found, using plain text"
        return
    }

    foreach file [lsort -dictionary [glob -nocomplain -directory $dir *.lang]] {
        LoadLanguageFile $file
    }
    if {[llength $LangOrder] == 0} {
        puts stderr "mied: no languages found in '$dir', using plain text"
    }

    BuildLanguageIndex
}

# Source one language file. A file that fails is reported and rolled back, so
# one broken language never stops the editor or leaves half of a language
# behind for the others to trip over.
proc LoadLanguageFile {path} {
    global Langs LangOrder LangCurrent

    set keep [llength $LangOrder]
    set LangCurrent ""

    if {[catch {source $path} err]} {
        foreach name [lrange $LangOrder $keep end] {
            array unset Langs $name,*
        }
        set LangOrder [lrange $LangOrder 0 [expr {$keep - 1}]]
        puts stderr "mied: error in language file '$path': $err"
        puts stderr "mied: that language is disabled"
        return 0
    }
    if {$LangCurrent eq ""} {
        puts stderr "mied: '$path' declares no language, skipped"
        return 0
    }
    return 1
}

# Extension index, built once every file is read so that a language loaded
# later can take over an extension. Lookups are case-insensitive.
proc BuildLanguageIndex {} {
    global Langs LangExt LangOrder

    array unset LangExt
    foreach name $LangOrder {
        foreach ext $Langs($name,extensions) {
            set LangExt([string tolower $ext]) $name
        }
    }
}

# Colour of a role, or empty when the role or the Config key is missing.
proc LangColor {role} {
    global Config LangColorKey

    if {![info exists LangColorKey($role)] \
            || ![info exists Config($LangColorKey($role))]} {
        return ""
    }
    return $Config($LangColorKey($role))
}

# Language from extension or shebang: a registered language name, or empty.
# An extension wins over a shebang, and among shebangs the first language
# loaded wins.
proc DetectLanguage {path content} {
    global Langs LangExt LangOrder

    set ext [string tolower [file extension $path]]
    if {$ext ne "" && [info exists LangExt($ext)]} {
        return $LangExt($ext)
    }

    set line [string trim [lindex [split $content \n] 0]]
    if {![string match "#!*" $line]} {
        return ""
    }
    foreach name $LangOrder {
        foreach pattern $Langs($name,shebang) {
            if {[regexp -- $pattern $line]} {
                return $name
            }
        }
    }
    return ""
}

# Comment prefix used by Ctrl+/. Languages without one comment with '#'.
proc CommentPrefix {lang} {
    global Langs

    if {$lang ne "" && [info exists Langs($lang,line_comment)] \
            && $Langs($lang,line_comment) ne ""} {
        return $Langs($lang,line_comment)
    }
    
    return "#"
}

# Drop the previous ctext classes and install the ones the language declares.
# ctext repaints every class from its own colour while it highlights, so the
# only fonts to set here are the two a declaration cannot express: keywords in
# bold and comments in the editor font.
proc ApplySyntaxHighlighting {ctext lang} {
    global Config Langs

    catch {::ctext::clearHighlightClasses $ctext}
    catch {::ctext::disableComments $ctext}

    if {!$Config(syntax_highlight) || $lang eq "" \
            || ![info exists Langs($lang,classes)]} {
        $ctext highlight 1.0 end
        return
    }

    foreach decl $Langs($lang,classes) {
        lassign $decl kind tag role spec
        set color [LangColor $role]
        if {$color eq ""} {
            puts stderr "mied: language '$lang': unknown colour role '$role'"
            continue
        }
        switch -- $kind {
            class  { ::ctext::addHighlightClass $ctext $tag $color $spec }
            regexp { ::ctext::addHighlightClassForRegexp $ctext $tag $color $spec }
            chars  { ::ctext::addHighlightClassForSpecialChars $ctext $tag $color $spec }
            char   { ::ctext::addHighlightClassWithOnlyCharStart $ctext $tag $color $spec }
            default {
                puts stderr "mied: language '$lang': unknown class kind '$kind'"
            }
        }
    }

    $ctext tag configure keywords -font $Config(font_bold)
    $ctext tag configure comments -font $Config(font)

    $ctext highlight 1.0 end
}

# Detect language from path/content and restyle the widget.
proc ApplySyntaxForBuffer {id} {
    global Buffers
    if {![SafeWindowExists $id]} return
    if {![IsEditor $id]} return

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
# kind is "editor" for a text document or "tree" for a file tree.
proc CreateBuffer {name path content {kind editor}} {
    global Buffers

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
    set Buffers($id,kind)      $kind
    set Buffers($id,lang)      ""
    if {$kind eq "editor"} {
        set Buffers($id,lang) [DetectLanguage $path $content]
    } else {
        set Buffers($id,hidden) [TreeHiddenDefault]
    }

    CreateWindow $id
    UpdateBufferList
    SetActiveBuffer $id

    return $id
}

# Empty untitled buffer.
proc NewBuffer {} {
    CreateBuffer "" "" ""
}

# File tree buffer; dir defaults to the active buffer's directory.
proc NewTreeBuffer {{dir ""}} {
    if {$dir eq ""} {
        set dir [TreeDefaultRoot]
    }
    if {![file isdirectory $dir]} {
        set dir [pwd]
    }
    set dir [file normalize $dir]

    CreateBuffer [TreeBufferName $dir] $dir "" tree
}

# Directory a new tree buffer should start in: the active buffer's directory,
# or the working directory when nothing file-backed is open.
proc TreeDefaultRoot {} {
    global Buffers ActiveBufferId

    if {$ActiveBufferId ne "" && [info exists Buffers($ActiveBufferId,path)]} {
        set path $Buffers($ActiveBufferId,path)
        if {$path ne ""} {
            if {[file isdirectory $path]} { return $path }
            return [file dirname $path]
        }
    }
    return [pwd]
}

# Title bar / sidebar label of a tree buffer.
proc TreeBufferName {dir} {
    set tail [string trim [file tail $dir]]
    if {$tail eq ""} { set tail $dir }
    return "Tree: $tail"
}

# Build the Tk window: title bar, status bar, and the body for the buffer
# kind (an editor, or a file tree).
proc CreateWindow {id} {
    global Buffers Config Desktop Layout

    set win $Desktop.buffer$id
    set kind $Buffers($id,kind)
    set Buffers($id,window) $win

    # Cascade new buffers around the desktop center instead of from its corner.
    update idletasks
    set desktopW [winfo width $Desktop]
    set desktopH [winfo height $Desktop]
    if {$desktopW <= 1} { set desktopW 1200 }
    if {$desktopH <= 1} { set desktopH 800 }

    set bufferW 500
    set bufferH 350
    set step 30
    set offset [expr {$id - 1}]
    set col [expr {$offset % 5 - 2}]
    set row [expr {int($offset / 5) - 1}]
    set x [expr {max(1, ($desktopW - $bufferW) / 2 + $col * $step)}]
    set y [expr {max(1, ($desktopH - $bufferH) / 2 + $row * $step)}]

    frame $win -bg $Config(border) -bd 1 -relief flat

    frame $win.titlebar -bg $Config(titlebar_bg) -height $Layout(titlebar_h) -cursor fleur
    grid $win.titlebar -row 0 -column 0 -sticky ew

    MakeFlatButton $win.titlebar minbtn $Layout(titlebtn_h) $Layout(titlebtn_h) "_" \
        $Config(ui_font) $Config(titlebar_bg) $Config(status_fg) \
        $Config(titlebar_bg) $Config(min_hover) [list MinimizeWindow $id] \
        [list -side right -padx 2]

    MakeFlatButton $win.titlebar closebtn $Layout(titlebtn_h) $Layout(titlebtn_h) "x" \
        $Config(ui_font) $Config(titlebar_bg) $Config(status_fg) \
        $Config(titlebar_bg) $Config(close_hover) [list CloseBuffer $id] \
        [list -side right -padx 6]

    if {$kind eq "tree"} {
        MakeFlatButton $win.titlebar folderbtn $Layout(titlebtn_h) $Layout(titlebtn_h) "..." \
            $Config(ui_font) $Config(titlebar_bg) $Config(status_fg) \
            $Config(titlebar_bg) $Config(hover_fg) [list ChooseTreeRoot $id] \
            [list -side right -padx 6]

        MakeFlatButton $win.titlebar dotbtn $Layout(titlebtn_h) $Layout(titlebtn_h) ".*" \
            $Config(ui_font) $Config(titlebar_bg) $Config(status_fg) \
            $Config(titlebar_bg) $Config(hover_fg) [list TreeToggleHidden $id] \
            [list -side right -padx 2]
        StyleTreeDotButton $id
    }

    label $win.titlebar.label -text "$Buffers($id,name)" \
        -bg $Config(titlebar_bg) -fg $Config(title_fg) \
        -font $Config(ui_font) -anchor w
    pack $win.titlebar.label -side left -padx 8 -pady 2 -fill x -expand 1

    frame $win.content -bg $Config(window_bg)
    grid $win.content -row 1 -column 0 -sticky nsew

    ttk::style configure Vertical.TScrollbar   -background $Config(scroll_bg)
    ttk::style configure Horizontal.TScrollbar -background $Config(scroll_bg)

    if {$kind eq "tree"} {
        BuildTreeBody $id
    } else {
        BuildEditorBody $id
    }

    # Sized from the scrollbars below; 17x15 is only the fallback size.
    frame $win.resize -bg $Config(border) -cursor sizing -width 17 -height 15

    frame $win.statusbar -bg $Config(titlebar_bg) -height $Layout(statusbar_h)
    grid $win.statusbar -row 2 -column 0 -sticky ew

    if {$kind eq "tree"} {
        label $win.statusbar.root -text $Buffers($id,path) \
            -bg $Config(titlebar_bg) -fg $Config(status_fg) \
            -font $Config(ui_font) -anchor w
        pack $win.statusbar.root -side left -padx 8

        label $win.statusbar.count -text "" \
            -bg $Config(titlebar_bg) -fg $Config(status_fg) \
            -font $Config(ui_font) -anchor e
        pack $win.statusbar.count -side right -padx 8
        TreeUpdateStatus $id
    } else {
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
    }

    if {$kind eq "editor"} {
        BuildFindBar $id
    }

    grid rowconfigure    $win 1 -weight 1
    grid columnconfigure $win 0 -weight 1

    if {$kind eq "editor"} {
        bind $win.content.ctext <KeyRelease>      +[list UpdateLineCounter $id]
        bind $win.content.ctext <ButtonRelease-1> +[list UpdateLineCounter $id]
        bind $win.content.ctext <<Modified>>      +[list OnTextChange $id]
    }

    place $win -x $x -y $y -width 500 -height 350
    update idletasks

    # The grip fills the corner between the scrollbars, so it follows their
    # thickness instead of scaling with the font. A tree buffer has only the
    # vertical bar, in which case the grip is square.
    set gripW [winfo width $win.content.vsb]
    set gripH 0
    if {[winfo exists $win.content.hsb]} {
        set gripH [winfo height $win.content.hsb]
    }
    if {$gripW > 1 && $gripH > 1} {
        $win.resize configure -width $gripW -height $gripH
    } elseif {$gripW > 1} {
        $win.resize configure -width $gripW -height $gripW
    }
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

    bind $win <Button-1> [list ActivateWindow $id]

    if {$kind eq "tree"} {
        focus $win.content.tree
    } else {
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
    }

    ActivateWindow $id
    UpdateLineCounter $id
}

# Body of an editor buffer: the ctext widget and its two scrollbars.
proc BuildEditorBody {id} {
    global Buffers Config

    set win $Buffers($id,window)

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
}

# Find/replace bar of an editor buffer.
proc BuildFindBar {id} {
    global Buffers Config Layout

    set win $Buffers($id,window)

    frame $win.findbar -bg $Config(toolbar_bg) -height $Layout(findbar_h)
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

    MakeFlatButton $win.findbar btn_case 26 $Layout(findbtn_h) "Aa" \
        $Config(ui_font) $Config(toolbar_bg) $Config(fg) \
        $Config(btn_hover_bg) $Config(hover_fg) ToggleFindCase \
        [list -row 0 -column 2 -padx 1 -pady $Layout(find_pad)]
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

        MakeFlatButton $win.findbar btn_$bname $bwidth $Layout(findbtn_h) $btext \
            $Config(ui_font) $Config(toolbar_bg) $btnFg \
            $Config(btn_hover_bg) $btnHoverFg [list $bcmd $id] \
            [list -row 0 -column $col -padx 1 -pady $Layout(find_pad)]

        incr col
    }

    bind $win.findbar.find    <Return>  [list FindNextInBuffer $id]
    bind $win.findbar.replace <Return>  [list ReplaceInBuffer $id]
    bind $win.findbar         <Escape>  [list HideFindBar $id]
}

# --- Window chrome --------------------------------------------------------

# Status bar: cursor position, line ratio, and language id.
proc UpdateLineCounter {id} {
    global Buffers
    if {![SafeWindowExists $id]} return
    if {![IsEditor $id]} return

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
        if {[winfo exists $win.findbar]} { grid forget $win.findbar }
        place forget $win.resize
        place $win -height [expr {[winfo reqheight $win.titlebar] + 2}]
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
    } elseif {[IsEditor $id]} {
        focus $win.content.ctext
    } else {
        focus $win.content.tree
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

# Open-file dialog.
proc OpenFile {} {
    set types {
        {{All Files}      *}
        {{Tcl Files}      {.tcl .tk}}
        {{C Files}        {.c .h .cpp .cc}}
        {{PHP Files}      {.php .phtml}}
        {{Go Files}       {.go}}
        {{Lua Files}      {.lua}}
        {{Shell Files}    {.sh .bash}}
        {{Markdown Files} {.md .markdown .mdown .mkdn .mkd}}
        {{Text Files}     {.txt}}
    }

    set filename [tk_getOpenFile -filetypes $types -title "Open File"]
    if {$filename eq ""} return
    OpenPath $filename
}

# Open a file in an editor buffer; an already-open file is only activated.
# Also used by file tree buffers when a file is double-clicked.
proc OpenPath {filename} {
    global Buffers

    if {$filename eq ""} return
    set filename [file normalize $filename]

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
    if {![IsEditor $id]} return

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
    if {![IsEditor $id]} return

    set types {
        {{All Files}      *}
        {{Tcl Files}      {.tcl}}
        {{C Files}        {.c .h}}
        {{PHP Files}      {.php .phtml}}
        {{Go Files}       {.go}}
        {{Lua Files}      {.lua}}
        {{Shell Files}    {.sh}}
        {{Markdown Files} {.md .markdown .mdown .mkdn .mkd}}
        {{Text Files}     {.txt}}
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

    if {[info exists Buffers($id,poll)]} {
        after cancel $Buffers($id,poll)
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

    ComputeLayout

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
        {tree    40 "Tree"     NewTreeBuffer}
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
    place .sidebar.header -x 0 -y 0 -relwidth 1 -height $Layout(header_h)

    listbox .sidebar.list -bg $Config(sidebar_bg) -fg $Config(list_fg) \
        -font $Config(ui_font) -bd 0 -highlightthickness 0 \
        -selectbackground $Config(sel_bg) -selectforeground $Config(sel_fg) \
        -activestyle none -exportselection 0
    place .sidebar.list -x 0 -y $Layout(header_h) -relwidth 1 -relheight 1 -height -$Layout(header_h)
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
    bind . <Control-t> NewTreeBuffer
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
    if {![IsEditor $id]} return

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
    if {![IsEditor $id]} return

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

# --- File tree ------------------------------------------------------------

# How often (ms) a tree buffer re-reads the directories it is showing.
set TreePollMs 2000

# Body of a tree buffer: a treeview over the root directory. Directories are
# read lazily on expand; a timer keeps the visible part in step with disk.
proc BuildTreeBody {id} {
    global Buffers Config

    set win $Buffers($id,window)
    set tree $win.content.tree

    ttk::style configure Mied.Treeview \
        -background $Config(window_bg) -fieldbackground $Config(window_bg) \
        -foreground $Config(list_fg) -borderwidth 0 \
        -font $Config(font) \
        -rowheight [expr {[font metrics $Config(font) -linespace] + 4}]
    ttk::style map Mied.Treeview \
        -background [list selected $Config(sel_bg)] \
        -foreground [list selected $Config(sel_fg)]

    ttk::treeview $tree -style Mied.Treeview -show tree -selectmode browse \
        -yscrollcommand [list $win.content.vsb set]
    ttk::scrollbar $win.content.vsb -orient vertical -command [list $tree yview]

    grid $tree            -row 0 -column 0 -sticky nsew
    grid $win.content.vsb -row 0 -column 1 -sticky ns
    grid rowconfigure    $win.content 0 -weight 1
    grid columnconfigure $win.content 0 -weight 1
    $tree column "#0" -stretch 1

    bind $tree <Button-1>        +[list ActivateWindow $id]
    bind $tree <Double-Button-1> [list TreeOnDoubleClick $id %W %x %y]
    bind $tree <<TreeviewOpen>>  [list TreeOnExpand $id %W]
    bind $tree <<TreeviewClose>> [list TreeOnCollapse $id %W]
    bind $tree <Return>          [list TreeOpenSelection $id]
    bind $tree <F5>              [list TreeRefreshNow $id]
    bind $tree <Control-h>       [list TreeToggleHidden $id]
    bind $tree <Control-H>       [list TreeToggleHidden $id]
    bind $tree <Control-w>       [list CloseBuffer $id]

    TreeLoadRoot $id
    TreeSchedulePoll $id
}

# Stub child id that gives a directory its expander arrow. It carries a
# control character, which a real file name does not.
proc TreeStubId {path} {
    return "$path\x01"
}

# True for the placeholder child that stands for "not read from disk yet".
proc TreeIsStub {id} {
    return [expr {[string first "\x01" $id] >= 0}]
}

# Real child paths of a directory node, in display order. A node that is no
# longer in the tree (a deleted root, say) simply has no children.
proc TreeChildren {tree dir} {
    if {![$tree exists $dir]} { return {} }

    set out [list]
    foreach child [$tree children $dir] {
        if {![TreeIsStub $child]} {
            lappend out $child
        }
    }
    return $out
}

# Directory listing in display order: subdirectories first, then files, each
# sorted by name. With hidden set, dot entries are listed as well; they are
# ordinary files on Unix, only conventionally skipped by shells. Both "*" and
# ".*" are matched because Unix globbing hides dot names from "*" while
# Windows does not, so duplicates and the "."/".." entries are dropped.
proc TreeListDir {dir {hidden 0}} {
    if {![file isdirectory $dir]} { return {} }

    set dirs [list]
    set files [list]
    foreach name [lsort -unique [glob -nocomplain -tails -directory $dir * .*]] {
        if {$name eq "." || $name eq ".."} continue
        if {!$hidden && [string match ".*" $name]} continue
        set path [file join $dir $name]
        if {[file isdirectory $path]} {
            lappend dirs $path
        } else {
            lappend files $path
        }
    }
    return [concat $dirs $files]
}

# Whether new tree buffers start by listing dot entries.
proc TreeHiddenDefault {} {
    global Config
    if {[info exists Config(tree_show_hidden)]} {
        return $Config(tree_show_hidden)
    }
    return 0
}

# Whether a tree buffer lists dot entries right now.
proc TreeShowHidden {id} {
    global Buffers
    if {[info exists Buffers($id,hidden)]} {
        return $Buffers($id,hidden)
    }
    return 0
}

# (Re)create the root node of a tree buffer and fill it from disk.
proc TreeLoadRoot {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    set tree $win.content.tree
    set root $Buffers($id,path)

    foreach item [$tree children {}] { $tree delete $item }

    if {![file isdirectory $root]} {
        TreeSetStatus $id "not found: $root"
        return
    }

    $tree insert {} end -id $root -text $root
    TreePopulate $id $root
    $tree item $root -open 1
    TreeSetStatus $id $root
}

# Insert the current listing of dir under its existing node.
proc TreeFill {id dir} {
    global Buffers

    set tree $Buffers($id,window).content.tree
    foreach path [TreeListDir $dir [TreeShowHidden $id]] {
        if {[file isdirectory $path]} {
            $tree insert $dir end -id $path -text [file tail $path]
            $tree insert $path end -id [TreeStubId $path] -text ""
        } else {
            $tree insert $dir end -id $path -text [file tail $path]
        }
    }
}

# Refresh a directory node from disk, keeping the node itself. Expanded
# subdirectories stay expanded and are refilled as well, so a change high up
# does not collapse what the user had opened.
proc TreePopulate {id dir} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set tree $Buffers($id,window).content.tree
    if {![$tree exists $dir]} return

    set expanded [TreeOpenDirs $tree $dir]
    foreach child [$tree children $dir] { $tree delete $child }
    TreeFill $id $dir

    foreach sub [lrange $expanded 1 end] {
        if {[$tree exists $sub] && [file isdirectory $sub]} {
            foreach child [$tree children $sub] { $tree delete $child }
            TreeFill $id $sub
            $tree item $sub -open 1
        }
    }
    TreeUpdateStatus $id
}

# Left status label: the root, or why it is no longer readable.
proc TreeSetStatus {id text} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    if {[winfo exists $win.statusbar.root]} {
        $win.statusbar.root configure -text $text
    }
}

# Right status label: top-level directories and files currently shown.
proc TreeUpdateStatus {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    if {![winfo exists $win.statusbar.count]} return

    set entries [TreeChildren $win.content.tree $Buffers($id,path)]
    set dirs 0
    foreach path $entries {
        if {[file isdirectory $path]} { incr dirs }
    }
    $win.statusbar.count configure -text \
        "$dirs dirs, [expr {[llength $entries] - $dirs}] files"
}

# A directory was expanded: read it from disk.
proc TreeOnExpand {id tree} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set item [$tree focus]
    if {$item eq "" || ![file isdirectory $item]} return
    TreePopulate $id $item
}

# A directory was collapsed: drop its children, the next open re-reads them.
proc TreeOnCollapse {id tree} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set item [$tree focus]
    if {$item eq ""} return
    TreeCollapseDir $tree $item
}

# Double click on a row opens a file in an editor buffer, so the single click
# that only selects a row (and raises the window) cannot open a file by
# accident. Directories are left to the treeview, which toggles them on a
# double click as well and fires <<TreeviewOpen>>/<<TreeviewClose>>, where the
# children are read from disk and dropped again.
proc TreeOnDoubleClick {id tree x y} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set item [$tree identify item $x $y]
    if {$item eq "" || [file isdirectory $item]} return

    OpenPath $item
}

# Drop the children of a collapsed directory, leaving a stub child behind: a
# node without children gets no expander arrow, and could then never be opened
# again.
proc TreeCollapseDir {tree dir} {
    foreach child [$tree children $dir] { $tree delete $child }
    if {[file isdirectory $dir]} {
        $tree insert $dir end -id [TreeStubId $dir] -text ""
    }
}

# Open or close a directory node.
proc TreeToggleDir {id dir} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set tree $Buffers($id,window).content.tree
    if {![$tree exists $dir]} return

    if {[$tree item $dir -open]} {
        $tree item $dir -open 0
        TreeCollapseDir $tree $dir
    } else {
        TreePopulate $id $dir
        $tree item $dir -open 1
    }
}

# Enter on the selected node: open a file, expand a directory.
proc TreeOpenSelection {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set item [$Buffers($id,window).content.tree focus]
    if {$item eq ""} return

    if {[file isdirectory $item]} {
        TreeToggleDir $id $item
    } else {
        OpenPath $item
    }
}

# F5: re-read the tree from disk, keeping what is expanded.
proc TreeRefreshNow {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set tree $Buffers($id,window).content.tree
    if {![$tree exists $Buffers($id,path)]} {
        TreeLoadRoot $id
        return
    }
    TreeRescan $id
}

# Re-read the directories that are currently expanded, so files created or
# deleted outside the editor show up.
proc TreeRescan {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    set tree $win.content.tree
    set root $Buffers($id,path)

    if {![$tree exists $root] || ![file isdirectory $root]} {
        TreeSetStatus $id "not found: $root"
        return
    }
    TreeSetStatus $id $root

    foreach dir [TreeOpenDirs $tree $root] {
        if {![$tree exists $dir]} continue
        if {![file isdirectory $dir]} {
            $tree delete $dir
            continue
        }
        if {[TreeListDir $dir [TreeShowHidden $id]] ne [TreeChildren $tree $dir]} {
            TreePopulate $id $dir
        }
    }
    TreeUpdateStatus $id
}

# Expanded directory nodes, the node itself first, then its open children.
proc TreeOpenDirs {tree item} {
    if {![$tree item $item -open]} { return {} }

    set out [list $item]
    foreach child [$tree children $item] {
        if {[file isdirectory $child]} {
            set out [concat $out [TreeOpenDirs $tree $child]]
        }
    }
    return $out
}

# Poll timer: keep a tree buffer in step with the filesystem.
proc TreeRefresh {id} {
    global Buffers
    unset -nocomplain Buffers($id,poll)
    if {![SafeWindowExists $id]} return

    TreeRescan $id
    TreeSchedulePoll $id
}

proc TreeSchedulePoll {id} {
    global Buffers TreePollMs
    if {![SafeWindowExists $id]} return
    set Buffers($id,poll) [after $TreePollMs [list TreeRefresh $id]]
}

# Show or hide dot entries in a tree buffer (Ctrl+H, or the ".*" title bar
# button). The tree is re-listed in place, so what is expanded stays expanded.
proc TreeToggleHidden {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set Buffers($id,hidden) [expr {!$Buffers($id,hidden)}]
    StyleTreeDotButton $id
    TreePopulate $id $Buffers($id,path)
}

# Paint the ".*" button: filled accent while dot entries are listed.
proc StyleTreeDotButton {id} {
    global Buffers Config
    if {![SafeWindowExists $id]} return

    set path $Buffers($id,window).titlebar.dotbtn
    if {![winfo exists $path]} return

    if {[TreeShowHidden $id]} {
        set bg $Config(accent)
        set fg $Config(sel_fg)
        set hoverBg $Config(accent)
        set hoverFg $Config(sel_fg)
    } else {
        set bg $Config(titlebar_bg)
        set fg $Config(status_fg)
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

# Pick another root directory for a tree buffer (the "..." title bar button).
proc ChooseTreeRoot {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set dir [tk_chooseDirectory -title "Open Folder" \
        -initialdir $Buffers($id,path) -mustexist 1]
    if {$dir eq ""} return

    set Buffers($id,path) [file normalize $dir]
    set Buffers($id,name) [TreeBufferName $Buffers($id,path)]
    UpdateWindowTitle $id
    UpdateStatus
    TreeLoadRoot $id
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
        -font [list [lindex $Config(font) 0] 18 bold]
    pack $win.body.title

    label $win.body.ver -text "Version $Mied(version)" \
        -bg $Config(bg) -fg $Config(fg) \
        -font [list [lindex $Config(font) 0] 10]
    pack $win.body.ver -pady {4 0}

    frame $win.body.spacer -bg $Config(bg) -height 30
    pack $win.body.spacer -fill x -expand 1

    label $win.body.copy -text "$Mied(authors)\n$Mied(license)" \
        -bg $Config(bg) -fg $Config(status_fg) \
        -font $Config(ui_font) -justify center \
        -wraplength 340
    pack $win.body.copy -pady {0 8}

    update idletasks
    wm geometry $win [format "%dx%d" \
        [expr {max(380, [winfo reqwidth $win])}] [winfo reqheight $win]]

    focus $win
}

# --- Argv ----------------------------------------------------------------

# Parse argv: mied.tcl [-config <file>] [file ...]
# -config is applied over the built-in defaults; the rest are file names.
# Returns the list of files to open.
proc ParseArgv {} {
    global argv Config

    set configFile ""
    set files [list]

    for {set i 0} {$i < [llength $argv]} {incr i} {
        set arg [lindex $argv $i]
        if {$arg eq "-config" || $arg eq "--config"} {
            incr i
            if {$i >= [llength $argv]} {
                puts stderr "mied: $arg requires a file argument"
                exit 1
            }
            set configFile [lindex $argv $i]
        } elseif {[string match "-*" $arg] && $arg ne "-"} {
            puts stderr "mied: unknown option '$arg'"
            puts stderr "usage: mied.tcl \[-config <config-file>\] \[file ...\]"
        } else {
            lappend files $arg
        }
    }

    if {![array size Config]} {
        LoadDefaultConfig
    }
    if {$configFile ne ""} {
        LoadConfigFile $configFile
    }

    return $files
}

# --- Start ----------------------------------------------------------------

# Parse argv, load the language files and the UI with the resulting config,
# then open the given files. A single file starts maximized; multiple files
# remain as regular independent buffers.
proc Main {} {
    set files [ParseArgv]
    LoadLanguages [LanguageDir]
    BuildUI

    if {[llength $files] == 0} return

    set opened 0
    foreach filename $files {
        if {$filename eq ""} continue
        set filename [file normalize $filename]
        if {![file exists $filename] || ![file isfile $filename]} {
            puts stderr "mied: cannot open '$filename': file does not exist or is not a regular file"
            continue
        }
        if {[catch {
            set fh [open $filename r]
            fconfigure $fh -encoding utf-8
            set content [read $fh]
            close $fh
        } err]} {
            puts stderr "mied: cannot open '$filename': $err"
            continue
        }
        CreateBuffer [file tail $filename] $filename $content
        incr opened
    }

    if {$opened == 1 && [llength $files] == 1} {
        global ActiveBufferId
        if {$ActiveBufferId ne ""} {
            update idletasks
            ToggleMaximize $ActiveBufferId
        }
    }
}

Main
