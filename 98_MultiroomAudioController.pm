package main;
use strict;
use warnings;

my @MultiroomAudioController_sets = (
    "0"               ,
    "1"               ,
    "2"               ,
    "3"	              ,
    "4"               ,
    "5"               ,
    "6"               ,
    "7"               ,
    "8"               ,
    "9"               ,
    "mute"            ,
    "volup"           ,
    "voldown"         ,
    "nextstream"      ,
    "defaultstream"   ,
    "forward"         ,
    "rewind"          ,
    "next"            ,
    "prev"            ,
    "play"            ,
    "pause"	          ,
    "stop"	          ,
    "statesave"       ,
    "stateload"       ,
    "plnext"          ,
    "plprev"          ,
    "trackinfo"       ,
    "offtimer"        ,
    "nextcontrol"	  ,
    "defaultcontrol"  
);


sub MultiroomAudioController_Initialize($) {
    my ($hash) = @_;
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
    $hash->{DefFn}      = 'MultiroomAudioController_Define';
    $hash->{UndefFn}    = 'MultiroomAudioController_Undef';
    $hash->{SetFn}      = 'MultiroomAudioController_Set';
    $hash->{AttrFn}     = 'MultiroomAudioController_Attr';
    $hash->{AttrList} =
          "volumeStepSize"
        . $readingFnAttributes;
}

sub MultiroomAudioController_Define($$) {
    my ($hash, $def) = @_;
    my @a = split('[ \t]+', $def);
    $hash->{name}  = $a[0];
    readingsSingleUpdate($hash,"state","defined",1);
    RemoveInternalTimer($hash);
    return undef;
}

sub MultiroomAudioController_Attr($$){
	my ($cmd, $name, $attr, $value) = @_;
    my $hash = $defs{$name};
	return undef;
}

sub MultiroomAudioController_Undef($$) {
    my ($hash, $arg) = @_; 
    RemoveInternalTimer($hash);
    return undef;
}


sub MultiroomAudioController_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set Snapcast" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $cmd = shift @param;

	
	if(!defined($MultiroomAudioController_sets{$cmd})) {
		return "Unknown argument $opt, choose one of " . join(" ", @MultiroomAudioController_sets);
	}
	return "$opt not yet implemented $value";
}


