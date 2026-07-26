#!/usr/bin/env tclsh
#
# Smalltalk Editor — рефакторенная версия
# =======================================
# Оригинальный код был переработан для устранения дублирования.
# Основные изменения:
#   • Все canvas-кнопки создаются через единую процедуру MakeFlatButton
#   • Панель Find/Replace и тулбар генерируются циклами из массивов конфигурации
#   • Повторяющиеся проверки существования окна вынесены в SafeWindowExists
#   • Общая логика поиска вынесена в FindInBuffer
#   • Добавлены комментарии ко всем нетривиальным участкам
#

package require Tk

# ============================================================================
# ГЛОБАЛЬНОЕ СОСТОЯНИЕ
# ============================================================================

array set Buffers {}          ;# Хранилище всех открытых буферов (id -> поля)
set NextBufferId 0            ;# Счётчик для генерации уникальных ID буферов
set ActiveBufferId ""         ;# ID текущего активного буфера
set ZIndex 100                ;# Z-индекс для поднятия окон на передний план
set CreatingBuffer 0          ;# Флаг блокировки повторного создания буфера
set SidebarVisible 1          ;# Флаг видимости боковой панели

# --- Состояние поиска/замены ---
set FindPattern ""            ;# Текущий шаблон поиска
set ReplacePattern ""         ;# Текущий шаблон замены
set FindCaseSensitive 0       ;# Флаг чувствительности к регистру

# ============================================================================
# КОНФИГУРАЦИЯ (светлая тема)
# ============================================================================
# Все цвета и шрифты собраны в одном месте для удобства кастомизации.

set Config(bg)           "#e8e8e8"
set Config(fg)           "#666666"
set Config(accent)       "#4a6fa5"
set Config(toolbar_bg)   "#c8c8c8"
set Config(sidebar_bg)   "#c8c8c8"
set Config(window_bg)    "#ffffff"
set Config(titlebar_bg)  "#c8c8c8"
set Config(border)       "#aaaaaa"
set Config(font)         {Helvetica 13}
set Config(title_font)   {Helvetica 11}
set Config(status_fg)    "#666666"
set Config(close_hover)  "#cc0000"
set Config(min_hover)    "#4a6fa5"
set Config(btn_bg)       "#e8e8e8"
set Config(btn_hover_bg) "#bbbbbb"
set Config(sep_color)    "#999999"
set Config(hover_fg)     "#000000"
set Config(title_fg)     "#444444"
set Config(list_fg)      "#444444"
set Config(insert_color) "#000000"
set Config(sel_bg)       "#4a6fa5"
set Config(sel_fg)       "#ffffff"
set Config(scroll_bg)    "#cccccc"
set Config(header_fg)    "#666666"
set Config(linenum_bg)   "#f0f0f0"
set Config(linenum_fg)   "#888888"
set Config(linenum_font) {Courier 11}

# ============================================================================
# УТИЛИТЫ
# ============================================================================

# --- SafeWindowExists ---
# Проверяет, существует ли окно буфера с заданным id.
# Используется перед любым обращением к виджетам буфера,
# чтобы избежать ошибок при закрытии/переключении.
proc SafeWindowExists {id} {
    global Buffers
    return [expr {[info exists Buffers($id,window)] && [winfo exists $Buffers($id,window)]}]
}

# --- AllBufferIds ---
# Возвращает отсортированный список ID всех существующих буферов.
# Централизует паттерн обхода массива Buffers.
proc AllBufferIds {} {
    global Buffers
    set ids [list]
    foreach name [array names Buffers *,id] {
        lappend ids $Buffers($name)
    }
    return [lsort -integer $ids]
}

# --- MakeFlatButton ---
# Универсальная фабрика плоских canvas-кнопок.
# Параметры:
#   parent   — родительский виджет (frame или окно)
#   name     — имя создаваемого canvas
#   width    — ширина кнопки
#   height   — высота кнопки
#   text     — текст на кнопке
#   font     — шрифт текста
#   bg       — фоновый цвет
#   fg       — цвет текста
#   hover_bg — цвет фона при наведении
#   hover_fg — цвет текста при наведении (пусто = не менять)
#   cmd      — команда по клику
#   packopts — дополнительные опции pack (например, -side right -padx 2)
#
# Создаёт прямоугольник-заглушку (tag "hit") для перехвата событий мыши
# и текстовую метку (tag "label"). bind вешается на "hit".
proc MakeFlatButton {parent name width height text font bg fg hover_bg hover_fg cmd geomopts} {
    set path ${parent}.${name}
    canvas $path -width $width -height $height -bg $bg \
        -highlightthickness 0 -cursor hand2

    # Определяем менеджер геометрии: pack (тулбар, titlebar)
    # или grid (findbar). Grid-опции содержат -row/-column.
    set isGrid 0
    foreach opt $geomopts {
        if {[string match "-row*" $opt] || [string match "-column*" $opt]} {
            set isGrid 1
            break
        }
    }
    if {$isGrid} {
        eval grid $path $geomopts
    } else {
        eval pack $path $geomopts
    }

    # Фоновый прямоугольник, покрывающий всю площадь кнопки
    $path create rectangle 0 0 $width $height -fill $bg -outline "" -tags hit
    # Текстовая метка по центру
    $path create text [expr {$width / 2}] [expr {$height / 2}] \
        -text $text -fill $fg -font $font -tags {hit label}

    # Клик
    $path bind hit <Button-1> $cmd

    # Наведение: меняем фон
    $path bind hit <Enter> [list $path configure -bg $hover_bg]
    $path bind hit <Leave> [list $path configure -bg $bg]

    # Наведение: меняем цвет текста, если задан hover_fg
    if {$hover_fg ne ""} {
        $path bind hit <Enter> +[list $path itemconfigure label -fill $hover_fg]
        $path bind hit <Leave> +[list $path itemconfigure label -fill $fg]
    }

    return $path
}

# --- MakeToolbarButton ---
# Специализация MakeFlatButton для кнопок тулбара.
# Все кнопки тулбара имеют одинаковую высоту (24) и одинаковые
# цвета наведения, поэтому параметры свёрнуты.
proc MakeToolbarButton {name width text cmd} {
    global Config
    MakeFlatButton .toolbar $name $width 24 $text \
        {Helvetica 10} $Config(toolbar_bg) $Config(fg) \
        $Config(btn_hover_bg) $Config(hover_fg) $cmd \
        [list -side left -padx 2 -pady 3]
}

# ============================================================================
# УПРАВЛЕНИЕ БУФЕРАМИ
# ============================================================================

# --- NewBuffer ---
# Создаёт новый пустой буфер с уникальным именем "untitled-N".
# Флаг CreatingBuffer предотвращает случайное двойное создание
# при быстром нажатии Ctrl+N.
proc NewBuffer {} {
    global NextBufferId Buffers CreatingBuffer

    if {$CreatingBuffer} return
    set CreatingBuffer 1

    incr NextBufferId
    set id $NextBufferId
    set name "untitled-$id"

    # Инициализация полей буфера
    set Buffers($id,id)       $id
    set Buffers($id,name)     $name
    set Buffers($id,path)     ""
    set Buffers($id,content)  ""
    set Buffers($id,modified) 0
    set Buffers($id,visible)  1

    CreateWindow $id
    UpdateBufferList
    SetActiveBuffer $id

    # Снимаем блокировку через 100 мс
    after 100 {set ::CreatingBuffer 0}
}

# --- CreateWindow ---
# Строит полное окно редактора для буфера с заданным id.
# Окно состоит из:
#   1. Заголовка (titlebar) с кнопками сворачивания и закрытия
#   2. Области редактирования (text + line numbers + scrollbars)
#   3. Панели поиска/замены (findbar, скрыта по умолчанию)
#   4. Строки состояния (statusbar)
#   5. Ручки изменения размера (resize handle)
proc CreateWindow {id} {
    global Buffers Config ZIndex Desktop

    set win $Desktop.buffer$id
    set Buffers($id,window) $win

    # Каскадное позиционирование: каждое новое окно смещено
    # на 30×25 пикселей от предыдущего, циклически по модулю 5.
    set x [expr {20 + ($id % 5) * 30}]
    set y [expr {20 + ($id % 5) * 25}]

    # Основной фрейм окна
    frame $win -bg $Config(border) -bd 1 -relief flat

    # === ЗАГОЛОВОК (titlebar) ===
    frame $win.titlebar -bg $Config(titlebar_bg) -height 26 -cursor fleur
    grid $win.titlebar -row 0 -column 0 -sticky ew

    # Кнопка сворачивания («_»)
    MakeFlatButton $win.titlebar minbtn 20 20 "_" \
        {Helvetica 12 bold} $Config(titlebar_bg) $Config(status_fg) \
        $Config(titlebar_bg) $Config(min_hover) [list MinimizeWindow $id] \
        [list -side right -padx 2]

    # Кнопка закрытия («x»)
    MakeFlatButton $win.titlebar closebtn 20 20 "x" \
        {Helvetica 12 bold} $Config(titlebar_bg) $Config(status_fg) \
        $Config(titlebar_bg) $Config(close_hover) [list CloseBuffer $id] \
        [list -side right -padx 6]

    # Метка с именем файла
    label $win.titlebar.label -text "$Buffers($id,name)" \
        -bg $Config(titlebar_bg) -fg $Config(title_fg) \
        -font $Config(title_font) -anchor w
    pack $win.titlebar.label -side left -padx 8 -pady 2 -fill x -expand 1

    # === ОБЛАСТЬ РЕДАКТИРОВАНИЯ ===
    frame $win.content -bg $Config(window_bg)
    grid $win.content -row 1 -column 0 -sticky nsew

    # Номера строк (canvas слева от текста)
    canvas $win.content.linenum -width 50 -bg $Config(linenum_bg) -highlightthickness 0
    grid $win.content.linenum -row 0 -column 0 -sticky ns

    # Основной текстовый виджет
    text $win.content.text -bg $Config(window_bg) -fg $Config(fg) \
        -font $Config(font) -wrap none \
        -yscrollcommand [list SyncScroll $id] \
        -xscrollcommand [list $win.content.hsb set] \
        -undo 1 -maxundo 100 \
        -insertbackground $Config(insert_color) \
        -selectbackground $Config(sel_bg) \
        -selectforeground $Config(sel_fg) \
        -borderwidth 0 -highlightthickness 0 \
        -padx 4 -pady 4

    # Полосы прокрутки
    ttk::scrollbar $win.content.vsb -orient vertical \
        -command [list $win.content.text yview]
    ttk::scrollbar $win.content.hsb -orient horizontal \
        -command [list $win.content.text xview]

    grid $win.content.text -row 0 -column 1 -sticky nsew
    grid $win.content.vsb  -row 0 -column 2 -sticky ns
    grid $win.content.hsb  -row 1 -column 0 -columnspan 2 -sticky ew
    grid rowconfigure    $win.content 0 -weight 1
    grid columnconfigure $win.content 1 -weight 1

    ttk::style configure Vertical.TScrollbar   -background $Config(scroll_bg)
    ttk::style configure Horizontal.TScrollbar -background $Config(scroll_bg)

    # === РУЧКА ИЗМЕНЕНИЯ РАЗМЕРА ===
    frame $win.resize -bg $Config(border) -width 12 -height 12 -cursor sizing
    place $win.resize -relx 1.0 -rely 1.0 -anchor se -y -22
    raise $win.resize

    # === СТРОКА СОСТОЯНИЯ ===
    frame $win.statusbar -bg $Config(titlebar_bg) -height 22
    grid $win.statusbar -row 2 -column 0 -sticky ew

    label $win.statusbar.lines -text "Col 1" \
        -bg $Config(titlebar_bg) -fg $Config(status_fg) \
        -font {Helvetica 9} -anchor w
    pack $win.statusbar.lines -side left -padx 8

    label $win.statusbar.info -text "" \
        -bg $Config(titlebar_bg) -fg $Config(status_fg) \
        -font {Helvetica 9} -anchor e
    pack $win.statusbar.info -side right -padx 8

    # === ПАНЕЛЬ ПОИСКА/ЗАМЕНЫ (скрыта по умолчанию) ===
    # Компактная grid-раскладка: поля ввода растягиваются,
    # кнопки имеют фиксированный размер. При изменении размера
    # окна панель просто сжимается/расширяется вместе с ним.
    frame $win.findbar -bg $Config(toolbar_bg) -height 26
    grid columnconfigure $win.findbar 0 -weight 1 -minsize 30
    grid columnconfigure $win.findbar 1 -weight 1 -minsize 30

    # Поле поиска
    entry $win.findbar.find -textvariable ::FindPattern \
        -bg $Config(window_bg) -fg $Config(fg) -font {Helvetica 11} \
        -highlightthickness 1 -highlightcolor $Config(accent)
    grid $win.findbar.find -row 0 -column 0 -sticky ew -padx 2 -pady 2

    # Поле замены
    entry $win.findbar.replace -textvariable ::ReplacePattern \
        -bg $Config(window_bg) -fg $Config(fg) -font {Helvetica 11} \
        -highlightthickness 1 -highlightcolor $Config(accent)
    grid $win.findbar.replace -row 0 -column 1 -sticky ew -padx 2 -pady 2

    # Генерация кнопок панели поиска из массива конфигурации.
    # Каждая запись: {имя ширина текст команда}
    set findbarButtons {
        {prev   26 "<"     FindPrevInBuffer}
        {next   26 ">"     FindNextInBuffer}
        {repl   42 "Repl"  ReplaceInBuffer}
        {all    30 "ReAll" ReplaceAllInBuffer}
        {close  22 "x"     HideFindBar}
    }
    set col 2
    foreach btn $findbarButtons {
        lassign $btn bname bwidth btext bcmd

        # Кнопка «закрыть» имеет красный цвет текста и красный hover
        if {$bname eq "close"} {
            set btnFg $Config(close_hover)
            set btnHoverFg "#ff4444"
        } else {
            set btnFg $Config(fg)
            set btnHoverFg $Config(hover_fg)
        }

        MakeFlatButton $win.findbar btn_$bname $bwidth 22 $btext \
            {Helvetica 9} $Config(toolbar_bg) $btnFg \
            $Config(btn_hover_bg) $btnHoverFg [list $bcmd $id] \
            [list -row 0 -column $col -padx 1 -pady 2]

        incr col
    }

    # Горячие клавиши внутри панели поиска
    bind $win.findbar.find    <Return>  [list FindNextInBuffer $id]
    bind $win.findbar.replace <Return>  [list ReplaceInBuffer $id]
    bind $win.findbar         <Escape>  [list HideFindBar $id]

    # Настройка растяжения основного окна
    grid rowconfigure    $win 1 -weight 1
    grid columnconfigure $win 0 -weight 1

    # === ПРИВЯЗКА СОБЫТИЙ ===

    # Обновление счётчика строк при вводе и клике мышью
    bind $win.content.text <KeyRelease> [list UpdateLineCounter $id]
    bind $win.content.text <ButtonRelease-1> [list UpdateLineCounter $id]

    # Первоначальное размещение окна на рабочем столе
    place $win -x $x -y $y -width 500 -height 350
    raise $win
    set ::ZIndex [expr {$::ZIndex + 1}]

    # --- Перетаскивание окна ---
    # Привязываемся к фону заголовка и метке, НО НЕ к кнопкам.
    bind $win.titlebar       <ButtonPress-1> [list StartDrag %W %X %Y $id]
    bind $win.titlebar       <B1-Motion>     [list OnDrag %W %X %Y $id]
    bind $win.titlebar       <Double-Button-1> [list ToggleMaximize $id]

    bind $win.titlebar.label <ButtonPress-1> [list StartDrag %W %X %Y $id]
    bind $win.titlebar.label <B1-Motion>     [list OnDrag %W %X %Y $id]
    bind $win.titlebar.label <Double-Button-1> [list ToggleMaximize $id]

    # --- Изменение размера ---
    bind $win.resize <ButtonPress-1> [list StartResize %W %X %Y $id]
    bind $win.resize <B1-Motion>     [list OnResize %W %X %Y $id]

    # --- Фокус и изменение текста ---
    bind $win.content.text <FocusIn>   [list SetActiveBuffer $id]
    bind $win.content.text <KeyRelease> +[list OnTextChange $id]

    # --- Поднятие окна на передний план по клику ---
    bind $win              <Button-1> [list RaiseWindow $id]
    bind $win.content.text <Button-1> [list RaiseWindow $id]

    # --- Горячие клавиши буфера ---
    bind $win.content.text <Control-s> [list SaveBuffer $id]
    bind $win.content.text <Control-w> [list CloseBuffer $id]
    bind $win.content.text <Control-o> OpenFile
    bind $win.content.text <Control-n> NewBuffer
    bind $win.content.text <Control-f> OpenFindDialog

    # Если буфер создан из файла — вставляем сохранённое содержимое
    if {$Buffers($id,content) ne ""} {
        $win.content.text insert 1.0 $Buffers($id,content)
    }

    focus $win.content.text
    RaiseWindow $id
    UpdateLineCounter $id
    UpdateLineNumbers $id
}

# --- SyncScroll ---
# Callback для синхронизации вертикальной прокрутки:
# обновляет положение scrollbar и перерисовывает номера строк.
proc SyncScroll {id args} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    # Передаём аргументы scrollbar'у
    eval [list $win.content.vsb set] $args
    # Перерисовываем номера строк
    UpdateLineNumbers $id
}

# --- UpdateLineNumbers ---
# Перерисовывает номера видимых строк в левом canvas.
# Определяет диапазон видимых строк через dlineinfo и
# вычисляет смещение Y для точного совпадения с текстом.
proc UpdateLineNumbers {id} {
    global Buffers Config
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    set textWidget $win.content.text
    set lineCanvas $win.content.linenum

    $lineCanvas delete all

    # Получаем индексы первой и последней видимой строки
    set top    [$textWidget index @0,0]
    set bottom [$textWidget index @0,[winfo height $textWidget]]
    set firstLine [expr {int([lindex [split $top "."] 0])}]
    set lastLine  [expr {int([lindex [split $bottom "."] 0])}]

    # Высота одной строки в пикселях
    set lineHeight [font metrics $Config(font) -linespace]

    # Вычисляем вертикальное смещение первой видимой строки
    set bbox [$textWidget dlineinfo $firstLine.0]
    if {$bbox eq ""} { set bbox [$textWidget dlineinfo 1.0] }
    if {$bbox ne ""} {
        set yOffset [lindex $bbox 1]
    } else {
        set yOffset 4
    }

    # Рисуем номера строк
    for {set line $firstLine} {$line <= $lastLine} {incr line} {
        set y [expr {$yOffset + ($line - $firstLine) * $lineHeight + $lineHeight / 2}]
        $lineCanvas create text 46 $y -text $line \
            -fill $Config(linenum_fg) -font $Config(linenum_font) -anchor e
    }

    # Автоматически подстраиваем ширину canvas под количество цифр
    set totalLines [lindex [split [$textWidget index end] "."] 0]
    set digits [string length $totalLines]
    set newWidth [expr {max(50, $digits * 10 + 20)}]
    $lineCanvas configure -width $newWidth
}

# --- UpdateLineCounter ---
# Обновляет метки в строке состояния: текущая позиция курсора
# и соотношение "текущая_строка:всего_строк".
proc UpdateLineCounter {id} {
    global Buffers Config
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    set textWidget $win.content.text

    set insertIdx   [$textWidget index insert]
    set currentLine [lindex [split $insertIdx "."] 0]
    set currentCol  [expr {[lindex [split $insertIdx "."] 1] + 1}]
    set totalLines  [lindex [split [$textWidget index end] "."] 0]

    $win.statusbar.lines configure -text "Col $currentCol"
    $win.statusbar.info  configure -text "$currentLine:$totalLines"

    UpdateLineNumbers $id
}

# --- MinimizeWindow ---
# Сворачивает/разворачивает окно буфера, скрывая всё содержимое
# и оставляя только заголовок высотой 28 пикселей.
proc MinimizeWindow {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)

    if {[info exists Buffers($id,visible)] && $Buffers($id,visible)} {
        # Свернуть: скрываем content, statusbar, findbar и ручку
        grid forget $win.content
        grid forget $win.statusbar
        grid forget $win.findbar
        place forget $win.resize
        place $win -height 28
        set Buffers($id,visible) 0
    } else {
        # Развернуть: восстанавливаем всё
        grid $win.content    -row 1 -column 0 -sticky nsew
        grid $win.statusbar  -row 2 -column 0 -sticky ew
        # findbar остаётся скрытой, пока не вызвана явно
        place $win.resize -relx 1.0 -rely 1.0 -anchor se -y -22
        raise $win.resize
        place $win -height 350
        set Buffers($id,visible) 1
    }
    UpdateBufferList
}

# --- RaiseWindow ---
# Поднимает окно буфера на передний план, увеличивая глобальный ZIndex.
proc RaiseWindow {id} {
    global ZIndex Buffers
    incr ZIndex
    if {[SafeWindowExists $id]} {
        raise $Buffers($id,window)
    }
}

# --- SetActiveBuffer ---
# Делает буфер активным: обновляет глобальную переменную,
# перекрашивает список в боковой панели и перемещает фокус.
proc SetActiveBuffer {id} {
    global ActiveBufferId Buffers
    set ActiveBufferId $id
    UpdateBufferList
    UpdateStatus
    if {[SafeWindowExists $id]} {
        focus $Buffers($id,window).content.text
    }
}

# --- OnTextChange ---
# Отслеживает изменения текста, сравнивая текущее содержимое
# виджета с сохранённым. Устанавливает/сбрасывает флаг modified.
proc OnTextChange {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    set current [$win.content.text get 1.0 end-1c]
    set saved   $Buffers($id,content)

    set Buffers($id,modified) [expr {$current ne $saved}]
    UpdateWindowTitle $id
    UpdateBufferList
    UpdateLineCounter $id
}

# --- UpdateWindowTitle ---
# Обновляет текст заголовка окна: добавляет «*» если есть несохранённые изменения.
proc UpdateWindowTitle {id} {
    global Buffers Config
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    set title "$Buffers($id,name)"
    if {$Buffers($id,modified)} { append title " *" }
    $win.titlebar.label configure -text $title
}

# --- UpdateBufferList ---
# Перестраивает список буферов в боковой панели.
# Для каждого буфера показывает имя, маркер изменений «*»
# и маркер свёрнутости «(min)». Активный буфер выделяется цветом.
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

# --- ActivateBufferByName ---
# Активирует буфер по имени из списка боковой панели.
# Убирает суффиксы « (min)» и « *» перед поиском.
proc ActivateBufferByName {name} {
    global Buffers
    set name [string trimright $name " (min)"]
    set name [string trimright $name " *"]
    foreach key [array names Buffers *,name] {
        if {$Buffers($key) eq $name} {
            set id [lindex [split $key ","] 0]
            if {[SafeWindowExists $id]} {
                raise $Buffers($id,window)
                SetActiveBuffer $id
            }
            break
        }
    }
}

# --- UpdateStatus ---
# Обновляет текст статуса в тулбаре: показывает путь к файлу
# активного буфера или его имя, если путь не задан.
proc UpdateStatus {} {
    global ActiveBufferId Buffers StatusLabel Config
    if {$ActiveBufferId eq ""} {
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

# ============================================================================
# ПЕРЕТАСКИВАНИЕ И ИЗМЕНЕНИЕ РАЗМЕРА ОКОН
# ============================================================================

# --- StartDrag / OnDrag ---
# Реализация drag-and-drop для перемещения окон.
# Запоминаем начальную позицию мыши и смещаем окно
# на разницу между текущей и начальной позицией.
proc StartDrag {widget x y id} {
    global DragStart DragWin
    set DragWin [winfo parent $widget]
    if {[winfo class $widget] eq "Label"} {
        set DragWin [winfo parent $DragWin]
    }
    set DragStart(x) $x
    set DragStart(y) $y
    RaiseWindow $id
}

proc OnDrag {widget x y id} {
    global DragStart DragWin
    if {![info exists DragWin]} return
    if {![winfo exists $DragWin]} return

    set dx [expr {$x - $DragStart(x)}]
    set dy [expr {$y - $DragStart(y)}]
    set newX [expr {[winfo x $DragWin] + $dx}]
    set newY [expr {max(1, [winfo y $DragWin] + $dy)}]
    place $DragWin -x $newX -y $newY
    set DragStart(x) $x
    set DragStart(y) $y
}

# --- StartResize / OnResize ---
# Реализация изменения размера окна за нижний-правый угол.
# Минимальный размер фиксирован: 200×150 пикселей.
proc StartResize {widget x y id} {
    global ResizeStart ResizeWin
    set ResizeWin [winfo parent $widget]
    set ResizeStart(x) $x
    set ResizeStart(y) $y
    set ResizeStart(w) [winfo width $ResizeWin]
    set ResizeStart(h) [winfo height $ResizeWin]
}

proc OnResize {widget x y id} {
    global ResizeStart ResizeWin
    if {![info exists ResizeWin]} return
    if {![winfo exists $ResizeWin]} return

    set dx [expr {$x - $ResizeStart(x)}]
    set dy [expr {$y - $ResizeStart(y)}]

    set newW [expr {max(200, $ResizeStart(w) + $dx)}]
    set newH [expr {max(150, $ResizeStart(h) + $dy)}]
    place $ResizeWin -width $newW -height $newH
}

# ============================================================================
# РАЗВЁРТЫВАНИЕ НА ВЕСЬ ЭКРАН
# ============================================================================

# --- ToggleMaximize ---
# Переключает окно между обычным размером (500×350) и полноэкранным
# (размер рабочего стола). Состояние хранится в Buffers($id,maximized).
proc ToggleMaximize {id} {
    global Buffers Desktop
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)

    if {[info exists Buffers($id,maximized)] && $Buffers($id,maximized)} {
        # Восстановить обычный размер
        place $win -x 20 -y 20 -width 500 -height 350
        set Buffers($id,maximized) 0
    } else {
        # Развернуть на весь рабочий стол
        set dw [winfo width $Desktop]
        set dh [winfo height $Desktop]
        place $win -x 0 -y 0 -width $dw -height $dh
        set Buffers($id,maximized) 1
    }
}

# ============================================================================
# ФАЙЛОВЫЕ ОПЕРАЦИИ
# ============================================================================

# --- OpenFile ---
# Открывает диалог выбора файла. Если файл уже открыт — активирует
# его буфер. Иначе создаёт новый буфер и загружает содержимое.
proc OpenFile {} {
    global Buffers NextBufferId

    set types {
        {{Text Files} {.txt}}
        {{All Files} *}
    }

    set filename [tk_getOpenFile -filetypes $types -title "Open File"]
    if {$filename eq ""} return

    # Проверяем, не открыт ли уже этот файл
    foreach key [array names Buffers *,path] {
        if {$Buffers($key) eq $filename} {
            set id [lindex [split $key ","] 0]
            RaiseWindow $id
            SetActiveBuffer $id
            return
        }
    }

    # Читаем файл в кодировке UTF-8
    if {[catch {
        set fh [open $filename r]
        fconfigure $fh -encoding utf-8
        set content [read $fh]
        close $fh
    } err]} {
        tk_messageBox -icon error -message "Cannot open file: $err"
        return
    }

    # Создаём буфер из файла
    incr NextBufferId
    set id $NextBufferId
    set name [file tail $filename]

    set Buffers($id,id)       $id
    set Buffers($id,name)     $name
    set Buffers($id,path)     $filename
    set Buffers($id,content)  $content
    set Buffers($id,modified) 0
    set Buffers($id,visible)  1

    CreateWindow $id
    UpdateBufferList
    SetActiveBuffer $id
}

# --- SaveBuffer ---
# Сохраняет содержимое буфера по известному пути.
# Если путь не задан (новый файл) — вызывает SaveAsBuffer.
proc SaveBuffer {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    if {$Buffers($id,path) eq ""} {
        SaveAsBuffer $id
        return
    }

    set win $Buffers($id,window)
    set content [$win.content.text get 1.0 end-1c]

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
    UpdateWindowTitle $id
    UpdateBufferList
    UpdateStatus
}

# --- SaveAsBuffer ---
# Открывает диалог «Сохранить как», обновляет путь и имя буфера,
# затем делегирует непосредственное сохранение SaveBuffer.
proc SaveAsBuffer {id} {
    global Buffers

    set types {
        {{Text Files} {.txt}}
        {{All Files} *}
    }

    set filename [tk_getSaveFile -filetypes $types -title "Save As"]
    if {$filename eq ""} return

    set Buffers($id,path) $filename
    set Buffers($id,name) [file tail $filename]

    SaveBuffer $id
}

# --- CloseBuffer ---
# Закрывает буфер. Если есть несохранённые изменения — спрашивает
# пользователя (Yes/No/Cancel). После закрытия активирует другой
# буфер или очищает статус, если буферов больше нет.
proc CloseBuffer {id} {
    global Buffers ActiveBufferId

    if {[info exists Buffers($id,modified)] && $Buffers($id,modified)} {
        set answer [tk_messageBox -icon warning -type yesnocancel \
            -message "Save changes to $Buffers($id,name)?"]
        if {$answer eq "yes"} {
            SaveBuffer $id
        } elseif {$answer eq "cancel"} {
            return
        }
    }

    if {[SafeWindowExists $id]} {
        destroy $Buffers($id,window)
    }

    # Удаляем все поля буфера из глобального массива
    foreach key [array names Buffers $id,*] {
        unset Buffers($key)
    }

    set ids [AllBufferIds]
    if {[llength $ids] > 0} {
        SetActiveBuffer [lindex $ids 0]
    } else {
        set ActiveBufferId ""
        UpdateStatus
    }

    UpdateBufferList
}

# ============================================================================
# БОКОВАЯ ПАНЕЛЬ
# ============================================================================

# --- ToggleSidebar ---
# Показывает/скрывает боковую панель, переключая geometry
# рабочего стола между полной шириной и смещением на 180 пикселей.
# Также обновляет размер всех развёрнутых окон.
proc ToggleSidebar {} {
    global SidebarVisible Config Desktop

    if {$SidebarVisible} {
        # Скрыть: рабочий стол занимает всю ширину
        place forget .sidebar
        place .desktop -x 0 -y 32 -relwidth 1 -width 0 -relheight 1 -height -32
        set SidebarVisible 0
    } else {
        # Показать: рабочий стол смещается вправо на 180px
        place .sidebar -x 0 -y 32 -width 180 -relheight 1 -height -32
        place .desktop -x 180 -y 32 -relwidth 1 -width -180 -relheight 1 -height -32
        set SidebarVisible 1
    }

    update idletasks

    # Обновляем размер развёрнутых окон под новый размер рабочего стола
    set dw [winfo width .desktop]
    set dh [winfo height .desktop]
    foreach key [array names ::Buffers *,maximized] {
        if {$::Buffers($key)} {
            set id [lindex [split $key ","] 0]
            set win $::Buffers($id,window)
            if {[winfo exists $win]} {
                place $win -x 0 -y 0 -width $dw -height $dh
            }
        }
    }
}

# ============================================================================
# ПОСТРОЕНИЕ ИНТЕРФЕЙСА
# ============================================================================

# --- BuildUI ---
# Создаёт главное окно приложения: тулбар, боковую панель,
# рабочий стол и привязывает глобальные горячие клавиши.
proc BuildUI {} {
    global Config Desktop SidebarList StatusLabel SidebarVisible

    wm title . "Smalltalk Editor"
    wm geometry . 1200x800
    . configure -bg $Config(bg)

    # === ТУЛБАР ===
    frame .toolbar -bg $Config(toolbar_bg) -height 32
    pack .toolbar -fill x -side top

    # Генерация кнопок тулбара из массива конфигурации.
    # Каждая запись: {внутреннее_имя ширина текст команда}
    set toolbarButtons {
        {sidebar 60 "Buffers"  ToggleSidebar}
        {new     40 "New"      NewBuffer}
        {open    40 "Open"     OpenFile}
        {save    40 "Save"     SaveActiveBuffer}
        {saveas  55 "Save As"  SaveAsActiveBuffer}
    }
    foreach btn $toolbarButtons {
        lassign $btn bname bwidth btext bcmd
        MakeToolbarButton $bname $bwidth $btext $bcmd
    }


    # Растягивающийся spacer и статусная метка
    frame .toolbar.spacer -bg $Config(toolbar_bg)
    pack .toolbar.spacer -side left -expand 1 -fill x

    label .toolbar.status -text "Ready" -fg $Config(status_fg) \
        -bg $Config(toolbar_bg) -font {Helvetica 10}
    pack .toolbar.status -side right -padx 10
    set StatusLabel .toolbar.status

    # === БОКОВАЯ ПАНЕЛЬ ===
    frame .sidebar -bg $Config(sidebar_bg) -width 180
    place .sidebar -x 0 -y 32 -width 180 -relheight 1 -height -32

    label .sidebar.header -text "BUFFERS" -fg $Config(header_fg) \
        -bg $Config(sidebar_bg) -font {Helvetica 9 bold}
    place .sidebar.header -x 0 -y 0 -width 180 -height 24

    listbox .sidebar.list -bg $Config(sidebar_bg) -fg $Config(list_fg) \
        -font $Config(font) -bd 0 -highlightthickness 0 \
        -selectbackground $Config(sel_bg) -selectforeground $Config(sel_fg) \
        -activestyle none -exportselection 0
    place .sidebar.list -x 0 -y 24 -width 180 -relheight 1 -height -24
    set SidebarList .sidebar.list

    # Клик по элементу списка активирует соответствующий буфер
    bind .sidebar.list <Button-1> {
        set idx [%W nearest %y]
        if {$idx >= 0} {
            set text [%W get $idx]
            ActivateBufferByName $text
        }
    }

    # === РАБОЧИЙ СТОЛ ===
    frame .desktop -bg $Config(bg)
    place .desktop -x 180 -y 32 -relwidth 1 -width -180 -relheight 1 -height -32
    set Desktop .desktop

    # При изменении размера окна обновляем развёрнутые буферы
    bind .desktop <Configure> {
        foreach key [array names ::Buffers *,maximized] {
            if {$::Buffers($key)} {
                set id [lindex [split $key ","] 0]
                set win $::Buffers($id,window)
                if {[winfo exists $win]} {
                    place $win -x 0 -y 0 -width [winfo width .desktop] -height [winfo height .desktop]
                }
            }
        }
    }

    # === ГЛОБАЛЬНЫЕ ГОРЯЧИЕ КЛАВИШИ ===
    bind all <Control-n> NewBuffer
    bind all <Control-o> OpenFile
    bind all <Control-s> SaveActiveBuffer
    bind all <Control-b> ToggleSidebar
    bind all <Control-f> OpenFindDialog
}

# --- SaveActiveBuffer / SaveAsActiveBuffer ---
# Обертки для сохранения текущего активного буфера.
proc SaveActiveBuffer {} {
    global ActiveBufferId
    if {$ActiveBufferId ne ""} {
        SaveBuffer $ActiveBufferId
    }
}

proc SaveAsActiveBuffer {} {
    global ActiveBufferId
    if {$ActiveBufferId ne ""} {
        SaveAsBuffer $ActiveBufferId
    }
}

# ============================================================================
# ПОИСК И ЗАМЕНА (встроенная панель)
# ============================================================================

# --- OpenFindDialog ---
# Открывает панель поиска для активного буфера.
proc OpenFindDialog {} {
    global ActiveBufferId
    if {$ActiveBufferId eq ""} return
    if {![SafeWindowExists $ActiveBufferId]} return
    ShowFindBar $ActiveBufferId
}

# --- ShowFindBar ---
# Отображает панель поиска над строкой состояния.
# Сдвигает ручку изменения размера, чтобы она не перекрывала панель.
proc ShowFindBar {id} {
    global Buffers Config
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    grid $win.findbar -row 3 -column 0 -sticky ew
    place $win.resize -relx 1.0 -rely 1.0 -anchor se -y -52
    raise $win.resize
    focus $win.findbar.find
}

# --- HideFindBar ---
# Скрывает панель поиска и возвращает ручку изменения размера
# в исходное положение над строкой состояния.
proc HideFindBar {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set win $Buffers($id,window)
    grid forget $win.findbar
    place $win.resize -relx 1.0 -rely 1.0 -anchor se -y -22
    focus $win.content.text
}

# --- FindInBuffer ---
# Универсальная процедура поиска, используемая и для «Найти далее»,
# и для «Найти назад». Параметр direction задаёт направление:
#   "forwards"  — искать вперёд от startIdx
#   "backwards" — искать назад от startIdx
#
# Возвращает пару {index length} или пустую строку, если не найдено.
proc FindInBuffer {id direction startIdx} {
    global FindPattern FindCaseSensitive Buffers
    if {![SafeWindowExists $id]} return ""

    set text $Buffers($id,window).content.text
    if {$FindPattern eq ""} return ""

    set switches [list -count length -$direction]
    if {!$FindCaseSensitive} { lappend switches -nocase }

    set idx [$text search {*}$switches -- $FindPattern $startIdx]

    # Wrap-around: если не нашли, ищем с противоположного конца
    if {$idx eq ""} {
        if {$direction eq "forwards"} {
            set idx [$text search {*}$switches -- $FindPattern 1.0]
        } else {
            set idx [$text search {*}$switches -- $FindPattern end]
        }
    }

    return [list $idx $length]
}

# --- FindNextInBuffer ---
# Находит следующее вхождение шаблона после текущего выделения
# (или после курсора, если выделения нет).
proc FindNextInBuffer {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set text $Buffers($id,window).content.text

    # Начинаем поиск после текущего выделения, иначе
    # «Найти далее» будет бесконечно находить ту же позицию.
    if {[$text tag ranges sel] ne ""} {
        set startIdx [$text index sel.last]
    } else {
        set startIdx [$text index "insert +1 chars"]
    }

    lassign [FindInBuffer $id forwards $startIdx] idx len
    if {$idx ne ""} {
        $text mark set insert $idx
        $text see $idx
        $text tag remove sel 1.0 end
        set endIdx [$text index "$idx + $len chars"]
        $text tag add sel $idx $endIdx
    }
}

# --- FindPrevInBuffer ---
# Находит предыдущее вхождение шаблона перед текущим выделением
# (или перед курсором, если выделения нет).
proc FindPrevInBuffer {id} {
    global Buffers
    if {![SafeWindowExists $id]} return

    set text $Buffers($id,window).content.text

    if {[$text tag ranges sel] ne ""} {
        set startIdx [$text index "sel.first -1 chars"]
    } else {
        set startIdx [$text index "insert -1 chars"]
    }

    lassign [FindInBuffer $id backwards $startIdx] idx len
    if {$idx ne ""} {
        $text mark set insert $idx
        $text see $idx
        $text tag remove sel 1.0 end
        set endIdx [$text index "$idx + $len chars"]
        $text tag add sel $idx $endIdx
    }
}

# --- ReplaceInBuffer ---
# Заменяет текущее выделение, если оно совпадает с шаблоном поиска,
# затем переходит к следующему вхождению.
proc ReplaceInBuffer {id} {
    global FindPattern ReplacePattern FindCaseSensitive Buffers
    if {![SafeWindowExists $id]} return

    set text $Buffers($id,window).content.text
    if {$FindPattern eq ""} return

    set selStart [$text index sel.first]
    set selEnd   [$text index sel.last]
    if {$selStart eq "" || $selEnd eq ""} {
        FindNextInBuffer $id
        return
    }

    # Проверяем, что выделение действительно совпадает с шаблоном
    set selected [$text get $selStart $selEnd]
    set pattern $FindPattern
    if {!$FindCaseSensitive} {
        set selected [string tolower $selected]
        set pattern  [string tolower $pattern]
    }

    if {$selected ne $pattern} {
        FindNextInBuffer $id
        return
    }

    $text delete $selStart $selEnd
    $text insert $selStart $ReplacePattern
    FindNextInBuffer $id
}

# --- ReplaceAllInBuffer ---
# Заменяет ВСЕ вхождения шаблона в буфере. Защита от бесконечного
# цикла: ограничение в 10 000 замен.
proc ReplaceAllInBuffer {id} {
    global FindPattern ReplacePattern FindCaseSensitive Buffers
    if {![SafeWindowExists $id]} return

    set text $Buffers($id,window).content.text
    if {$FindPattern eq ""} return

    set switches [list -count length -forwards]
    if {!$FindCaseSensitive} { lappend switches -nocase }

    set count 0
    set idx 1.0

    while {1} {
        set found [$text search {*}$switches -- $FindPattern $idx]
        if {$found eq ""} break
        $text delete $found [$text index "$found + $length chars"]
        $text insert $found $ReplacePattern
        set idx [$text index "$found + [string length $ReplacePattern] chars"]
        incr count
        if {$count > 10000} break
    }

    if {$count > 0} {
        $text tag remove sel 1.0 end
    }
}

# ============================================================================
# ТОЧКА ВХОДА
# ============================================================================

BuildUI
NewBuffer
focus .desktop
