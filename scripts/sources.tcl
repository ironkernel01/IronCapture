# Vivado source registration for the stream and DDR interfaces.
namespace eval ironcapture {
    variable root [file normalize [file join [file dirname [info script]] ..]]
}
proc ironcapture::path {rtlnet entry} {
    variable root
    if {[string match "cores/rtlnet_common/*" $entry]} {return [file join $rtlnet $entry]}
    if {[string match "ip/rtlnet_csi2_rx/*" $entry]} {return [file join $root $entry]}
    error "Unknown receiver source path: $entry"
}
proc ironcapture::read_list {tree list_name seen_var dirs_var} {
    upvar 1 $seen_var seen $dirs_var dirs
    set stream [open [path $tree $list_name]]
    try {set contents [read $stream]} finally {close $stream}
    foreach raw [split $contents "\n"] {
        set line [string trim [lindex [split $raw #] 0]]
        if {$line eq ""} {continue}
        if {[regexp {^-f\s+(\S+)$} $line -> child]} {
            read_list $tree $child seen dirs
        } elseif {[regexp {^\+incdir\+(.+)$} $line -> dir]} {
            lappend dirs [path $tree $dir]
        } else {
            set path [file normalize [path $tree $line]]
            if {![file isfile $path]} {error "Missing capture source: $line"}
            if {$path ni $seen} {lappend seen $path}
        }
    }
}
proc ironcapture_add_stream_sources {rtlnet} {
    set root $ironcapture::root
    # Vivado compares include filenames literally, including NTFS junctions.
    set rtlnet [string trim [exec git -C $rtlnet rev-parse --show-toplevel]]
    set stream [open [file join $root rtlnet-common.lock.json]]
    try {set lock [read $stream]} finally {close $stream}
    foreach field {repository tree core} {
        if {![regexp [format {"%s"\s*:\s*"([^"]+)"} $field] $lock -> value]} {error "Invalid common primitive pin"}
        set $field $value
    }
    set remote [string trim [exec git -C $rtlnet remote get-url origin]]
    regsub {^https://[^/@]+@github\.com/} $remote https://github.com/ remote
    if {[string trim [exec git -C $rtlnet rev-parse HEAD:$core]] ne $tree || $remote ne $repository ||
        [string trim [exec git -C $rtlnet status --porcelain -- $core]] ne ""} {
        error "RTLNet common primitives differ from IronCapture's pin"
    }
    set files {}; set dirs [list [file join $rtlnet cores/rtlnet_common/hdl]]
    ironcapture::read_list $rtlnet ip/rtlnet_csi2_rx/hdl/rtlnet_csi2_rx.f files dirs
    lappend files [file normalize [file join $rtlnet cores/rtlnet_common/hdl/rtlnet_technology.svh]]
    add_files -norecurse $files
    set_property include_dirs [lsort -unique [concat [get_property include_dirs [current_fileset]] $dirs]] [current_fileset]
}
proc ironcapture_add_sources {rtlnet} {
    ironcapture_add_stream_sources $rtlnet
    foreach name {ironcapture_control.sv ironcapture_writer.sv ironcapture_top.v} {
        add_files -norecurse [file join $ironcapture::root hdl $name]
    }
}
