package main;
use strict;
use warnings;
use Data::Dumper;

my %MultiroomAudioController_sets = (
    "0"              =>1,
    "1"              =>1,
    "2"              =>1,
    "3"	             =>1,
    "4"              =>1,
    "5"              =>1,
    "6"              =>1,
    "7"              =>1,
    "8"              =>1,
    "9"              =>1,
    "mute"           =>2,
    "volup"          =>2,
    "voldown"        =>2,
    "forward"        =>3,
    "rewind"         =>3,
    "next"           =>3,
    "previous"           =>3,
    "play"           =>3,
    "pause"	         =>3,
    "stop"	         =>3,
    "random"         =>3,
    "single"         =>3,
    "repeat"         =>3,
    "statesave"      =>3,
    "stateload"      =>3,
    "chanup"         =>3,
    "chandown"       =>3,
    "trackinfo"      =>3,
    "offtimer"       =>2,
    "stream"     	 =>2,
    "copystate"      =>2,
    "control"        =>2,
    "streamreset"    =>2
);


sub MultiroomAudioController_Initialize($) {
    my ($hash) = @_;
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
    $hash->{DefFn}      = 'MultiroomAudioController_Define';
    $hash->{UndefFn}    = 'MultiroomAudioController_Undef';
    $hash->{NotifyFn}   = 'MultiroomAudioController_Notify';
    $hash->{SetFn}      = 'MultiroomAudioController_Set';
    $hash->{AttrFn}     = 'MultiroomAudioController_Attr';
    $hash->{NotifyOrderPrefix} = "80-"; 
    $hash->{AttrList} =
          "mrSystem:SNAPCAST soundSystem:MPD mr soundMapping ttsMapping defaultTts defaultStream defaultSound numberHelper playlistPattern stateSaveDir seekStep seekDirect:percent,seconds seekStepSmall seekStepSmallThreshold"
        . $readingFnAttributes;
}

sub MultiroomAudioController_Define($$) {
    my ($hash, $def) = @_;
    my @a = split('[ \t]+', $def);
    my $name= $hash->{name}  = $a[0];
    readingsSingleUpdate($hash,"state","defined",1);
    RemoveInternalTimer($hash);
    $hash->{NOTIFYDEV}="undefined";
    $attr{$name}{mrSystem}                  = 'SNAPCAST'         unless (exists($attr{$name}{mrSystem}));
    $attr{$name}{soundSystem}               = 'MPD'              unless (exists($attr{$name}{soundSystem}));
    $attr{$name}{seekStep}                  = '10'               unless (exists($attr{$name}{seekStep}));
    $attr{$name}{seekDirect}                = 'percent'          unless (exists($attr{$name}{seekDirect}));
    $attr{$name}{seekStepSmall}             = '2'                unless (exists($attr{$name}{seekStepSmall}));
    $attr{$name}{seekStepSmallThreshold}    = '8'                unless (exists($attr{$name}{seekStepSmallThreshold}));
    Log3 $name,3,"MAC DEFINED";
    return undef;
}

sub MultiroomAudioController_Attr($$){
	my ($cmd, $name, $attr, $value) = @_;
    my $hash = $defs{$name};
    Log3 $name,3,"MAC Attr set: $attr, $value";
    if ($cmd eq "set"){
    	if($attr eq "mr"){
    		$hash->{NOTIFYDEV}=$value;
    		$hash->{NOTIFYDEV} .= ",".$hash->{SOUND} if defined($hash->{SOUND}) and $hash->{SOUND} ne "";
    		MultiroomAudioController_getReadings($hash,$value);

    	}
    	if($attr eq "soundMapping"){
    		$hash->{soundMapping}=$value;
    		MultiroomAudioController_setNotifyDef($hash);
    	}
    }
    my $out=Dumper($hash);
    Log3 $name,3,$out;
	return undef;
}

sub MultiroomAudioController_setNotifyDef($){
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $oldsound=$hash->{SOUND};
    if (!$init_done){
      InternalTimer(gettimeofday()+5,"MultiroomAudioController_setNotifyDef", $hash, 0);
      return "init not done";
    }
	$hash->{NOTIFYDEV}=AttrVal($name,"mr","undefined");
    my @soundMapping = split(",",$hash->{soundMapping});
    delete ($hash->{SOUND});
    foreach my $map (@soundMapping){
    	my @mapping = split(":",$map);
    	$hash->{SOUND} = $mapping[1] if(ReadingsVal($name,"stream","") eq $mapping[0]);
    }
    MultiroomAudioController_getReadings($hash,$hash->{SOUND}) if $hash->{SOUND} ne $oldsound;

    $hash->{NOTIFYDEV} .= ",".$hash->{SOUND} if defined($hash->{SOUND}) and $hash->{SOUND} ne "";
}

sub MultiroomAudioController_Undef($$) {
    my ($hash, $arg) = @_; 
    RemoveInternalTimer($hash);
    return undef;
}

sub MultiroomAudioController_Notify($$){
  my ($hash, $dev_hash) = @_;
  my $ownName = $hash->{NAME}; # own name / hash
  my $devName = $dev_hash->{NAME}; # own name / hash
  my $devType = $dev_hash->{TYPE}; # own name / hash
  my $updateFlag=0;
  return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
 
  my $devName = $dev_hash->{NAME}; # Device that created the events
 
  my $events = deviceEvents($dev_hash,1);
  return if( !$events );
 
  readingsBeginUpdate($hash);
  foreach my $event (@{$events}) {
    $event = "" if(!defined($event));
    my ($name,$value) = split( ": ", $event );
    if($devType =~/MPD/i){
    	$name=~s/volume/sound_volume/;
    	$name=~s/state/sound_state/;
    }
    if($devType =~/Snapcast/i){
    	$name=~s/state/mr_state/;
    	$name=~s/name/mr_name/;
    	$updateFlag = 1 if($name eq "stream");
    }
        	
    readingsBulkUpdateIfChanged($hash,$name,$value );
    Log3 $ownName,3,"MAC got reading from $devName: $devType: $name|$value";
    # processing $event with further code
  }
  readingsEndUpdate($hash,1);
  Log3 $ownName,3,"MAC Notify_done";
  MultiroomAudioController_setNotifyDef($hash) if $updateFlag == 1;
  return undef;
}

sub MultiroomAudioController_Set($@) {
	my ($hash, @param) = @_;
	return '"set Snapcast" needs at least one argument' if (int(@param) < 2);	
	my $name = shift @param;
	my $cmd = shift @param;
    my $val = shift @param;
	my $mrname=AttrVal($name,"mr","undefined");
	my $numbername = AttrVal($name,"numberHelper","undefined");
	my $soundname= defined($hash->{SOUND}) ? $hash->{SOUND} : '' ;
    if (not defined($defs{$soundname})){
        MultiroomAudioController_setNotifyDef($hash) if not defined($defs{$soundname});
	   $soundname= defined($hash->{SOUND}) ? $hash->{SOUND} : '' ;
    }
    my $mrhash=$defs{$mrname};
    my $soundhash= defined ($defs{$soundname}) ? $defs{$soundname} : '';
	my $soundtyp=AttrVal($name,"soundSystem","");
	my $soundModuleHash=$modules{$soundtyp};
	my $numberHash=$defs{$numbername};

	if(!defined($MultiroomAudioController_sets{$cmd})) {
		my @cList = keys %MultiroomAudioController_sets;
		return "Unknown argument $cmd, choose one of " . join(" ", @cList);
	}
	# clear:noArg clear_readings:noArg mpdCMD next:noArg outputenabled0:0,1 pause:noArg play playfile playlist previous:noArg random:noArg repeat:noArg reset:noArg single:noArg stop:noArg toggle:noArg updateDb:noArg volume:slider,0,1,100 volumeDown:noArg volumeUp:noArg
	return MultiroomAudioController_Error($hash,"no sound backend connected or soundsystem not defined, check soundMapping and soundSystem attributes",1)
		if $MultiroomAudioController_sets{$cmd}>2 && (not defined ($soundhash) || $soundhash eq '' || not defined ($soundModuleHash) || $soundModuleHash eq '');
	return MultiroomAudioController_Error($hash,"no multiroom backend connected, check mr attribute",1) if $MultiroomAudioController_sets{$cmd}>1 && (!defined ($mrhash) || $mrhash eq '');
	return MultiroomAudioController_Error($hash,"no numberHelper backend connected, check numberHelper attribute",1) if ($MultiroomAudioController_sets{$cmd}==1 && ( !defined ($numberHash) || $numberHash eq ''));
	if($cmd eq "play"){
		CallFn($soundname,"SetFn",$defs{$soundname},$soundname,$cmd);
		return undef
	}
	if($cmd eq "pause"){
		CallFn($soundname,"SetFn",$defs{$soundname},$soundname,$cmd);
		return undef;
	}
	if($cmd eq "toggle"){
		CallFn($soundname,"SetFn",$defs{$soundname},$soundname,$cmd);
		return undef;
	}
	if($cmd eq "stop"){
		CallFn($soundname,"SetFn",$defs{$soundname},$soundname,$cmd);
		return undef;
	}
	if($cmd eq "next" || $cmd eq "previous"){
        CallFn($soundname,"SetFn",$defs{$soundname},$soundname,$cmd);
		return undef;
	}
	if($cmd eq "forward" || $cmd eq "rewind"){
        my ($elapsed,$total) = split (":",ReadingsVal($name,"time",""));
        $total=int($total);
        if( not defined($total) || $total <= 0){
            return undef;
        }
        my $percent = $elapsed / $total;
        my $step = 0.01*(0.01*AttrVal($name,"seekStepSmallThreshold",0) > $percent ? AttrVal($name,"seekStepSmall",3) : AttrVal($name,"seekStep",7));
        Log3 $name,3,"MAC2: $elapsed, $total, $percent";
        $percent +=$step if $cmd eq "forward";
        $percent -=$step if $cmd eq "rewind";
        $percent = 0  if $percent<0;
        $percent = 0.99 if $percent > 0.99;
        my $newint=int($percent*$total);
        my $new=$percent*$total;
        Log3 $name,3,"MAC2: $step, $elapsed, $total, $percent, $new, $newint";

        CallFn($soundname,"SetFn",$defs{$soundname},$soundname,"seekcur",int($percent*$total));       
        return undef;
	}
	if($cmd eq "random"){
        CallFn($soundname,"SetFn",$defs{$soundname},$soundname,$cmd);		
        return undef;
	}
	if($cmd eq "single"){
        CallFn($soundname,"SetFn",$defs{$soundname},$soundname,$cmd);		
        return undef;
	}
	if($cmd eq "repeat"){
        CallFn($soundname,"SetFn",$defs{$soundname},$soundname,$cmd);		
        return undef;
	}
    if($cmd eq "chanup" || $cmd eq "chandown"){ # next playlist or specific playlist if number was entered before
        # get lists based on regexp. Seperate those playlists that have a 2 or 3 digit number in them.
        my $filter=AttrVal($name,"playlistPattern",".*");
        my @allPlaylists=split(":",ReadingsVal($name,"playlistcollection",""));
        my @filteredPlaylists=  grep { /$filter/ } @allPlaylists;
        return "no playlists found" if(@filteredPlaylists == 0);
        my @filteredPlaylistsWithNumbers = grep { /\d{2,3}/ }  @filteredPlaylists;
        my @filteredPlaylistsWithoutNumbers = grep { !/\d{2,3}/ }  @filteredPlaylists;
        # delete existing playlist array and crate a reference to an empty array to pupulate it afterwards
        delete $hash->{PLARRAY};
        $hash->{PLARRAY}=[];
        # iterate the items with a number first, to try to put the to the slot according to their number. 
        foreach my $item (@filteredPlaylistsWithNumbers){
            # for each one push it to the according position. pushPlArray will ensure no slot is used twice and increase accordingly
            $item=~/(\d{2,3})/;
            MultiroomAudioController_pushPlArray($hash,$item,$1);
        }
        # do the same for the other items and push them into the array
        foreach my $item (@filteredPlaylistsWithoutNumbers){
            MultiroomAudioController_pushPlArray($hash,$item);
        }
        # next 3 lines, build an array of pl numbers, get the number of the current one and its index in the index array. This could probably be done better. 
        my $mpdplaylist = defined ($soundhash->{'.playlist'}) ? $soundhash->{'.playlist'} : '';
        my (@indexes) = grep { defined(${$hash->{PLARRAY}}[$_]) } (0 .. @{$hash->{PLARRAY}});
        my ($current) = grep { ${$hash->{PLARRAY}}[$_] eq $mpdplaylist } (0 .. @{$hash->{PLARRAY}});
        my ($currentindex) = grep { defined($current) && defined($indexes[$_]) && $indexes[$_] eq $current } (0 .. @indexes-1);

        # for next or prev, just increase the number or decrease the number based on $cmd, call getPlName(number)
        if($cmd eq 'chanup'){
            $currentindex = not(defined($currentindex)) || $currentindex == @indexes-1 ? 0 : $currentindex+1;
        }
        if($cmd eq 'chandown'){
            $currentindex = not(defined($currentindex)) || $currentindex == 0 ? @indexes-1 : $currentindex-1;
        }
        # TODO: for direct, kust call get PlName
        # TODO: load the state file for the playlistname
        # load the playlist
        CallFn($soundname,"SetFn",$defs{$soundname},$soundname,"playlist",${$hash->{PLARRAY}}[$indexes[$currentindex]]);
        Log3 $name,3,"MAC2: CallFn $soundname, SetFn, ".$defs{$soundname}.", $soundname, playlist, ".${$hash->{PLARRAY}}[$indexes[$currentindex]];
        readingsSingleUpdate($hash,"playlistnumber",$indexes[$currentindex],1);
        CallFn($soundname,"SetFn",$defs{$soundname},$soundname,"play");       
        Log3 $name,3,"MAC2: ". $currentindex;
        Log3 $name,3,"MAC2: ". "current: $current, currentindex: $currentindex" if defined($currentindex);
        Log3 $name,3,"MAC2: ". $soundhash->{'.playlist'};
        Log3 $name,3,"MAC2: ". @indexes;

        Log3 $name,3,"MAC2: ". "new playlist number: ";
        Log3 $name,3,"MAC2: ". $indexes[$currentindex];
        Log3 $name,3,"MAC2: ". "new playlist name: ";
        Log3 $name,3,"MAC2: ". ${$hash->{PLARRAY}}[$indexes[$currentindex]];
        # execute stateload 
        # play
   
        return undef;
    }
    if($cmd eq "volup"){
        CallFn($mrname,"SetFn",$defs{$mrname},$mrname,"volume","up");
        return undef;
    }
    if($cmd eq "voldown"){
        CallFn($mrname,"SetFn",$defs{$mrname},$mrname,"volume","down");
        return undef;
    }

    if($cmd eq "stream"){
        my $targetStream="";
        if(defined($val)){
            $targetStream = $val;
        }
        return undef if $targetStream eq "";
        CallFn($mrname,"SetFn",$defs{$mrname},$mrname,"stream",$targetStream);
        return undef;
    }

    if($cmd eq "copystate"){
        my $defaultstream = AttrVal($name,"defaultStream","");
        return undef if $defaultstream eq "";
        CallFn($mrname,"SetFn",$defs{$mrname},$mrname,"stream",$defaultstream);
        return undef;
    }

    if($cmd eq "control"){
        my $defaultstream = AttrVal($name,"defaultStream","");
        return undef if $defaultstream eq "";
        CallFn($mrname,"SetFn",$defs{$mrname},$mrname,"stream",$defaultstream);
        return undef;
    }
    if($cmd eq "streamreset"){
        my $defaultstream = AttrVal($name,"defaultStream","");
        return undef if $defaultstream eq "";
        CallFn($mrname,"SetFn",$defs{$mrname},$mrname,"stream",$defaultstream);
        return undef;
    }





	return MultiroomAudioController_Error($hash,"$cmd not yet implemented",2) ;
}

sub MultiroomAudioController_pushPlArray(@){
    my ($hash,$item,$number) = @_;
    my $name = $hash->{NAME};
    $number=1 unless defined($number);
    while (defined(${$hash->{PLARRAY}}[$number])){
        $number++;
    }
    ${$hash->{PLARRAY}}[$number]=$item;
    $hash->{CURRENTPL} = $number if(ReadingsVal($name,"playlistname","") eq $item);
    return $number;
}

sub MultiroomAudioController_Error($$$){ # hier noch TTS feedback einbauen je nach errorlevel
	my ($hash,$msg,$level) = @_;
	return $msg;
}

 sub MultiroomAudioController_getReadings($$){
 	my ($hash, $module) = @_;
 	my $name = $hash->{NAME};
    if (!$init_done){
      InternalTimer(gettimeofday()+10,"MultiroomAudioController_getReadings", $hash, $module);
      return "init not done";
    }
 	return undef unless defined($defs{$module});
 	my $modhash=$defs{$module};
 	my $readings=$modhash->{READINGS};
 	my $modname=$modhash->{NAME};
 	my $devType=$modhash->{TYPE};
 	my $updateFlag=0;
 	Log3 $name,3,"MAC getting readings from $modname";
 	readingsBeginUpdate($hash);
 	while ( my ($key, $value) = each %{$readings} ){
 	    if($devType =~/MPD/i){
    		$key=~s/volume/sound_volume/;
    		$key=~s/state/sound_state/;
    	}
    	if($devType =~/Snapcast/i){
    		$key=~s/state/mr_state/;
    		$key=~s/name/mr_name/;
    		$updateFlag = 1 if($key eq "stream");
    	}
		readingsBulkUpdateIfChanged($hash,$key,$value->{VAL} );
		Log3 $name,3,"MAC getReading got reading $key from $modname, ".$value->{VAL};
 	}
 	readingsEndUpdate($hash,1);
 	MultiroomAudioController_setNotifyDef($hash) if $updateFlag == 1;
    if(ReadingsVal($name,"stream","") eq "" && $module eq AttrVal($name,"mr","")){
        InternalTimer(gettimeofday()+10,"MultiroomAudioController_getReadings", $hash, $module);
    }
 	return undef;
 }




