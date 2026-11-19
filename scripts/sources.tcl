# Read the complete camera RTL from its pinned original checkout. Usage in
# a Vivado project: source sources.tcl; ironcapture_add_sources <RTLNet-root>
namespace eval ironcapture {
    variable root [file normalize [file join [file dirname [info script]] ..]]
}
proc ironcapture::read_list {tree list_name seen_var dirs_var} {
    upvar 1 $seen_var seen $dirs_var dirs
    set stream [open [file join $tree $list_name]]
    try {set contents [read $stream]} finally {close $stream}
    foreach raw [split $contents "\n"] {
        set line [string trim [lindex [split $raw #] 0]]
        if {$line eq ""} {continue}
        if {[regexp {^-f\s+(\S+)$} $line -> child]} {
            read_list $tree $child seen dirs
        } elseif {[regexp {^\+incdir\+(.+)$} $line -> dir]} {
            lappend dirs [file join $tree $dir]
        } else {
            set path [file normalize [file join $tree $line]]
            if {![file isfile $path]} {error "Missing RTLNet file: $line"}
            if {$path ni $seen} {lappend seen $path}
        }
    }
}
proc ironcapture_add_sources {rtlnet} {
    set root $ironcapture::root
    set stream [open [file join $root receiver.lock.json]]
    try {set lock [read $stream]} finally {close $stream}
    foreach field {repository commit filelist} {
        if {![regexp [format {"%s"\s*:\s*"([^"]+)"} $field] $lock -> value]} {error "Invalid receiver.lock.json"}
        set $field $value
    }
    set remote [string trim [exec git -C $rtlnet remote get-url origin]]
    regsub {^https://[^/@]+@github\.com/} $remote https://github.com/ remote
    if {[string trim [exec git -C $rtlnet rev-parse HEAD]] ne $commit || $remote ne $repository ||
        [string trim [exec git -C $rtlnet status --porcelain --untracked-files=no -- cores/rtlnet_common cores/rtlnet_csi2_rx]] ne ""} {
        error "RTLNet receiver checkout differs from IronCapture's revision"
    }
    set files {}; set dirs [list [file join $rtlnet cores/rtlnet_common/hdl]]
    ironcapture::read_list $rtlnet $filelist files dirs
    lappend files [file join $rtlnet cores/rtlnet_common/hdl/rtlnet_technology.svh]
    foreach name {ironcapture_control.sv ironcapture_writer.sv ironcapture_top.v} {
        lappend files [file join $root hdl $name]
    }
    add_files -norecurse $files
    set_property include_dirs [lsort -unique [concat [get_property include_dirs [current_fileset]] $dirs]] [current_fileset]
}
