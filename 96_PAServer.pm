package main;
use strict;
use warnings;
use Switch;
use Data::Dumper;

my $PAServer_LogLevelDebug = 1;
my $PAServer_LogLevelNormal = 1;
my $PAServer_LogLevelCritical =1;
my $PAServer_pactl="/usr/bin/pactl";
my $PAServer_standard_interval = 10;
my %PAServer_gets = (
	"tbd"	=> "x"
);

my %PAServer_sets = (
    "tbd"   => "x"
);
# the following is a collection of Regex-Expressions used to parse the output from the pactl tool in order to get information about the pulseaudio sinks and sink-inputs active
my $PAServer_getpapatterns = {"sinks" =>
                      {"reg" => qr/^Sink #(\d+)/,
                       "state" => qr/State: (.*)/,
                       "name" => qr/Name: (.*)/,
                       "volume" => qr/Volume: front-left:.*\s(\d+)%/,
                       "mute" => qr/Mute: (.*)/,
                       "slaves" => qr/slaves = \"(.*)\"/,
                       "driver" => qr/Driver: (.*)/,
                       "owner" => qr/Owner Module: (\d+)/},
                     "sink-inputs" =>
                      {"reg" => qr/^Sink Input #(\d+)/,
                       "name" => qr/Name: (.*)/,
                       "sink" => qr/Sink: (.*)/,
                       "client" => qr/Client: (.*)/,
                       "volume" => qr/Volume: front-left:.*\s(\d+)%/,
                       "mute" => qr/Mute: (.*)/,
					   "medianame" => qr/media\.name = \"(.*)\"/,
                       "owner" => qr/Owner Module: (\d+)/}};
	   
sub PAServer_Initialize($) {
    my ($hash) = @_;

    $hash->{DefFn}      = 'PAServer_Define';
    $hash->{UndefFn}    = 'PAServer_Undef';
    $hash->{SetFn}      = 'PAServer_Set';
    $hash->{GetFn}      = 'PAServer_Get';
	$hash->{WriteFn}    = 'PAServer_Write';
    #$hash->{AttrFn}     = 'PAServer_Attr';
    $hash->{ReadFn}     = 'PAServer_Read';
    $hash->{Clients} =
        ":PAClient:";
    my %mc = (    "1:PAClient"   	=> ".*"    );
    $hash->{MatchList} = \%mc;
    $hash->{AttrList} =
          "startcmd stopcmd interval "
        . $readingFnAttributes;
	

}

sub PAServer_Define($$) {
    my ($hash, $def) = @_;
    my @a = split('[ \t]+', $def);
        $hash->{name}  = $a[0];
    $hash->{ip} = (defined($a[2])) ? $a[2] : "localhost"; 
    $hash->{NOTIFYDEF} = "global";
    readingsSingleUpdate($hash,"state","defined",1);
    RemoveInternalTimer($hash);
    InternalTimer(gettimeofday()+5, "PAServer_processCmd", $hash, 0);  # initiate the regular update process
    return undef;
}

sub PAServer_Undef($$) {
    my ($hash, $arg) = @_; 
    # TODO: delete modules combined and tunnels
    RemoveInternalTimer($hash);
    BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));
    return undef;
}

sub PAServer_getTunnelId($$){
	my ($hash, $client) = @_;
	return undef unless defined ($hash->{MODULES}->{sinks});
	foreach my $key (%{$hash->{MODULES}->{sinks}}){
		if (defined($hash->{MODULES}->{sinks}->{$key}->{name}) && $hash->{MODULES}->{sinks}->{$key}->{name} eq $client.".tunnel"){
			return $key;
		}
	}
	return undef;
}

sub PAServer_createTunnel($$){
	my ($hash, $client) = @_;
	my $clienthash = $defs{$client};
	my $cmd="load-module module-tunnel-sink sink_name=$client.tunnel server=$clienthash->{ip}";
	PAServer_PushCmdStack($hash,$cmd);
	return undef;
}
sub PAServer_createCombine($$$){
    my ($hash,$client,$desiredClients) = @_;
	$desiredClients=$client.".tunnel,".$desiredClients;
	my $cmd = "load-module module-combine-sink sink_name=$client.combine slaves=$desiredClients";
	PAServer_PushCmdStack($hash,$cmd);
	return undef;
}

sub PAServer_registerSlave($$$){
	my ($hash, $client,$slave) = @_;
	my $clienthash = $defs{$client};
	readingsSingleUpdate($hash,"state","defined",1);
}

sub PAServer_deleteModule($$){
	my ($hash, $module) = @_;
	my $cmd="unload-module $module";
	PAServer_PushCmdStack($hash,$cmd);
	return undef;
}


sub PAServer_Write($$$){
	my ($hash, $client,$command) = @_;
	my ($cmd,$arg) = split('[ \t]+', $command);
	$arg = "none" unless defined($arg);
	my $clienthash = $defs{$client};
	switch($cmd){
		case "DESIRED_MASTER"	{
			readingsSingleUpdate($hash,"client.$client.desiredmaster",$arg,1);
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday(), "PAServer_processCmd", $hash, 0);  # initiate the regular update process
		}
		case "online"		{
			PAServer_registerClient($hash,$client);
			PAServer_createTunnel($hash,$client) unless (PAServer_getTunnelId($hash,$client));
			readingsBeginUpdate($hash);readingsBulkUpdateIfChanged($hash,"clients.$client.online","on");readingsEndUpdate($hash,1);
		}
		case "deleted"   {
			PAServer_unregisterClient($hash,$client);
			readingsSingleUpdate($hash,"clients.$client.online","deleted",1);
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday(), "PAServer_processCmd", $hash, 0);  # initiate the regular update process
		}
		case "offline"   {
			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash,"clients.$client.online","off");
			readingsBulkUpdate($hash,"clients.$client.tunnel","down");
			readingsEndUpdate($hash,1);
			RemoveInternalTimer($hash);
			InternalTimer(gettimeofday(), "PAServer_processCmd", $hash, 0);  # initiate the regular update process 
		}
	}
	return undef;
}

sub PAServer_Get($@) {
	my ($hash, @param) = @_;
	return '"get PAServer" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	if(!$PAServer_gets{$opt}) {
		my @cList = keys %PAServer_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	return "to be defined";
}

sub PAServer_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set PAServer" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join("", @param);
	
	if(!defined($PAServer_sets{$opt})) {
		my @cList = keys %PAServer_sets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	return "not yet implemented";
}




sub PAServer_doUpdate($){
    # this function is called as blocking call 
    my ($string) = @_;
    return unless(defined($string));
    my @a = split("\\|" ,$string); 
    my $pa;
    my $output = $a[0]; # Name
    my $ip = $a[1];
	if(@a>2){
		my $cmd = "$PAServer_pactl -s $ip $a[2] 2>&1";
		my @result=`$cmd`;
	}
    # the following foreach loop goes through every line returned by pactl list and parses it into a hash of sinks and sink-indexes
    foreach my $key (keys %{$PAServer_getpapatterns}){
    	my $cmd = "$PAServer_pactl -s $ip list ".$key." 2>&1";
        my @result=`$cmd`;
        if(@result>0 && $result[0]=~/refused/){
             return  $output."|error";
		exit;
	}
    	my $index=0;
        for (my $lineno=0;$lineno<@result;$lineno++){
            if($result[$lineno] =~$PAServer_getpapatterns->{$key}->{"reg"}){
                $index=$1;
            }else{
                foreach my $subkey (keys %{$PAServer_getpapatterns->{$key}}){
                if ($result[$lineno]=~$PAServer_getpapatterns->{$key}->{$subkey}){
                        $pa->{$key}{$index}{$subkey}=$1
                    }
                }
            }
        }
	}
    my $json = encode_json $pa; #used to serialize the hash in order to return it as a string
    return  $output."|".$json;
}

sub PAServer_getSinkInput($$){
	my ($hash, $client) = @_;
	foreach my $key (keys (%{$hash->{MODULES}->{'sink-inputs'}})){
		my $value=$hash->{MODULES}->{'sink-inputs'}{$key};
		return ($key,$value->{sink}) if($value->{medianame} eq $client);
	}
	return (undef, undef)
}

sub PAServer_finishedUpdate($){
    my ($string) = @_;
    return unless(defined($string));
    my ($h,$ret) = split("\\|",$string);
    my $hash = $defs{$h};
    my $name = $hash->{NAME};
	my @actualClients;
	my @desiredClients;
    delete($hash->{helper}{RUNNING_PID});
    if($ret=~/error/){ # if an error occurs, this means that pulseaudio is not running or not running currectly. We will consider it as offline.
        readingsBeginUpdate($hash);readingsBulkUpdateIfChanged($hash,"pulseaudio","offline");readingsEndUpdate($hash,1);
		delete $hash->{MODULES};
		IOWrite ($hash, $name,"offline")  unless ($hash->{TYPE} eq "PAServer");
    }else{
        readingsBeginUpdate($hash);readingsBulkUpdateIfChanged($hash,"pulseaudio","online");
		if($hash->{TYPE} eq "PAClient"){
			IOWrite ($hash, $hash->{name},"online");
			readingsBulkUpdateIfChanged($hash,"tunnel","requested") unless ReadingsVal($hash->{name},"tunnel",0) eq "established";
		}
		readingsEndUpdate($hash,1);
        $hash->{MODULES} = decode_json($ret); # we store the sinks and sink-indexes in the hash.
        $hash->{MODULES_TIME} = time();
		
		
		# is this a server? this code is also used by PACLient
		if($hash->{TYPE} eq "PAServer"){
			# the following sections check the current pulseaudio configuration, compares it with how it should be and initiates the necessary changes
			# this includes the creation and deletion of tunnel-sinks and combine sinks (for multiroom) and the moving of existing sink-inputs (which means there is playback running) to the appropriate sink
			# this ensures that in all scenarios, even if clients just disappear, pulseaudio will be adjusted to coninue in the expected way. 
			# iterate all sinks if this is a server
			# 1. iterate through all sinks
			my $clienthash;
			delete $hash->{helper}{sinktypes};
			while (my($key,$value) = each (%{$hash->{MODULES}->{sinks}})){
				# is it a tunnel sink?
				if($value->{name}=~/tunnel/){
					if($value->{name}=~/^(.+)\.tunnel$/ && defined($clienthash=$defs{$1}) && ReadingsVal($hash->{name},"clients.$1.online","") eq "on"){  # is it a valid tunnel sink
						my $clientname=$1;
						readingsBeginUpdate($hash);readingsBulkUpdateIfChanged($hash,"clients.$clientname.tunnel","established");readingsEndUpdate($hash,1);
						readingsBeginUpdate($clienthash);readingsBulkUpdateIfChanged($clienthash,"tunnel","established");readingsEndUpdate($clienthash,1);
						$hash->{helper}{sinks}{$clientname}=$key unless $hash->{helper}{sinktypes}{$clientname} eq "combine";
					}else{
						PAServer_deleteModule($hash,$value->{owner});
					}
				# is it a combine sink (so more than 1 client listening to the same source / multiroom sync)
				}elsif($value->{name}=~/combine/){
					if($value->{name}=~/^(.+)\.combine$/ && defined($clienthash=$defs{$1})){  # is it a valid combine sink
						my $clientname=$1;
						my $slaves=$value->{slaves};
						## den client aus den slaves extrahieren, wenn er nicht selbst drin ist ist tunnel ungueltig
						if(not ($slaves=~s/$clientname\.tunnel\,// || $slaves=~s/\,$clientname\.tunnel//)){
							PAServer_deleteModule($hash,$value->{owner});
						}else{
							@actualClients = split(",",$slaves);
							@desiredClients = split(",",PAServer_getAttached($hash,$clientname,1));
							@desiredClients = sort { $a cmp $b } @desiredClients; # sort both arrays in order to make them comparable for equality
							@actualClients  = sort { $a cmp $b } @actualClients ;
							if(not(@desiredClients ~~ @actualClients)){
								PAServer_deleteModule($hash,$value->{owner});
							}else{
								readingsBeginUpdate($hash);readingsBulkUpdateIfChanged($hash,"clients.$clientname.slaves",$slaves);readingsEndUpdate($hash,1);
								$hash->{helper}{sinks}{$clientname}=$key;
								$hash->{helper}{sinktypes}{$clientname}="combine";
							}
						}						
						Log 1, "PAServer $hash->{NAME} Slavesvon $clientname: $slaves | desired: ".PAServer_getAttached($hash,$clientname,1);

					}else{
						PAServer_deleteModule($hash,$value->{owner});
					}
				}
			}
			# iterate clients and, if there is a client that does not have a combine module  but shoudl have one, create it
			# in the same foreach loop also redirect sink input if needed
			foreach my $clientname (@{$hash->{CLIENTS}}){
				my ($sinkinput,$actualsink) = PAServer_getSinkInput($hash,$clientname);
				my $sink = $hash->{helper}{sinks}{$clientname};
				# Log 1, "PA: clientname: $clientname, sinkinput: $sinkinput, sink: ".$sink.", actualsink: $actualsink";
				if(defined($sinkinput) && defined($sink)){
					PAServer_moveSinkInput($hash,$sinkinput,$sink) if($sink != $actualsink);
				}
				my $found_combine = 0;
				while (my($key,$value) = each (%{$hash->{MODULES}->{sinks}})){
					$found_combine=1 if ($value->{name}=~/$clientname\.combine/);
				}
				if(not($found_combine)){
					my $desiredClients = PAServer_getAttached($hash,$clientname,1);
					if($desiredClients ne ""){
						PAServer_createCombine($hash,$clientname,$desiredClients);
					}else{
						readingsBeginUpdate($hash);readingsBulkUpdateIfChanged($hash,"clients.$clientname.slaves","");readingsEndUpdate($hash,1);
					}
				}
			}


		}
		#
		#
		#
		#
		#

		# check if there are commands in the cmdStack (commands are executed directly after an update to ensure there is no slippage in information consistency)
		if($hash->{cmdStack} && @{$hash->{cmdStack}}){
			PAServer_processCmd($hash, shift @{$hash->{cmdStack}});
			$hash->{protCmdPend} = " CMDs_done" unless (@{$hash->{cmdStack}});
			return undef;
		}
	}
	InternalTimer(gettimeofday()+$PAServer_standard_interval, "PAServer_processCmd", $hash, 0); #initiate the next update 
    return undef;
}

sub PAServer_abortUpdate($){
     my ($hash) = @_;
     delete($hash->{helper}{RUNNING_PID});
     InternalTimer(gettimeofday()+$PAServer_standard_interval, "PAServer_processCmd", $hash, 0);
     return;
}

sub PAServer_processCmd($$){
	my ($hash, $cmd) = @_;
	my $name = $hash->{NAME};
	my $args = $name."|".$hash->{ip};
	if(defined($cmd)){
		$args.="|".$cmd->{cmd};
	}
	$hash->{helper}{RUNNING_PID} = BlockingCall("PAServer_doUpdate", $args, "PAServer_finishedUpdate", 5,"PAServer_abortUpdate",$hash) unless(exists($hash->{helper}{RUNNING_PID}));
}

sub PAServer_PushCmdStack($$) {
  my ($hash, $cmd) = @_;
  my @arr = ();
  my $name = $hash->{NAME};
  
  if(!$hash->{cmdStack}){  # this is a new 'burst' of messages (i got inspired for this CmdStack code from CUL_HM, thanks to Martin!)
    $hash->{cmdStack} = \@arr;
  }
  foreach my $element (@{$hash->{cmdStack}}) {
	if ($element->{cmd} eq $cmd){
		$element->{timestamp} = time();
		return undef;
	}
  }
  push(@{$hash->{cmdStack}}, { cmd => $cmd, timestamp => time()});
  my $entries = scalar @{$hash->{cmdStack}};
  $hash->{protCmdPend} = $entries." CMDs_pending";
}

sub PAServer_registerClient($$){
	my ($hash, $client) = @_;
	my @arr = ();
	if(!$hash->{CLIENTS}){ 
		$hash->{CLIENTS} = \@arr;
    }
	if (not (grep {$_ eq $client} @{$hash->{CLIENTS}})) {
		push(@{$hash->{CLIENTS}},$client);
	}
}

sub PAServer_moveSinkInput($$$){
	my ($hash, $sinkinput,$sink) = @_;
	my $cmd = "move-sink-input $sinkinput $sink";
	PAServer_PushCmdStack($hash,$cmd);
}
sub PAServer_unregisterClient($$){
	my ($hash, $client) = @_;
	if($hash->{CLIENTS}){
		my @clients = @{$hash->{CLIENTS}};
		my @temp = grep { $clients[$_] eq $client } 0..$#clients;
		my $i = 0;
		for (@temp) {
			splice(@clients, $_-$i, 1);
			$i++;
		}
		@{$hash->{CLIENTS}} = @clients;
	}
	readingsSingleUpdate($hash,"client.$client.desiredmaster","",1);
}



sub PAServer_getAttached($$$){
	# selector = 0 not implemented yet
	# selector = 1 return only such clients that have an established tunnel
	# selector = 2 return all clients that would like to be slaves no matter if they are already ready for it
	my ($hash, $client,$selector) = @_;
	my $result="";
	foreach (@{$hash->{CLIENTS}}){
		if($client eq ReadingsVal($hash->{name},"client.$_.desiredmaster","")){
			if($selector == 2){ #do we want to get the full list of desired even if not online and tunnel established?
					$result.="," unless ($result eq "");
					$result.=$_.".tunnel";
			}elsif($selector ==1){ # we do only want to get the full list of clients that are actually online and with an established tunnel
				if(ReadingsVal($hash->{name},"clients.$_.online","") eq "on" && ReadingsVal($_,"tunnel","") eq "established"){
					$result.="," unless ($result eq "");
					$result.=$_.".tunnel";
				}
			}
		}
	}
	return $result;
}




1;

=pod
=begin html

<a name="PAServer"></a>
<h3>PAServer</h3>
<ul>
    <i>PASeerver</i> is the server side module for the FHEM Pulseaudio Multiroom Solution. It automates the process of managing
	the dynamic creation and deletion of Pulseaudio Tunnel and Combine Sinks in order to create a truly synced multiroom audiio experience
	Pulseaudio capable of transfering audio to any other computer running Pulseaudio, and also to more than one at once. PAServer integrates this capability
	into FHEM and combined with the PAClient module it enables the FHEM user to have several clients listen to different or the same source of audio in sync or independently on demand
	The PAServer is only useful if there is at least one PAClient while the multiroom feature is only useable with at least 2 clients obviously.
	Direct playback on the server is not yet implemented
    <br><br>
    <a name="PAServerdefine"></a>
    <b>Define</b>
    <ul>
        <code>define <name> PAServer <ip></code>
        <br><br>
        Example: <code>define MyServer PAServer 127.0.0.1</code>
        <br><br>
        The ip parameter gives the hostname or ip of the machine where pulseaudio is running on and where the audio source is going to be played
		Currently the PAServer and PAClient framework is work in progress. It is planned to directly integrate with the mpd sound server using the FHEM MPD module.
        See <a href="http://fhem.de/commandref.html#define">commandref#define</a> 
        for more info about the define command.
    </ul>
    <br>
    
    <a name="PAServerset"></a>
    <b>Set</b><br>
    <ul>
        <code>set <name> <option> <value></code>
        <br><br>
        See <a href="http://fhem.de/commandref.html#set">commandref#set</a> 
        for more info about the set command.
        <br><br>
        Options:
        <ul>
              <li><i>tbd</i><br>
                  tbd</li>
        </ul>
    </ul>
    <br>
</ul>

=end html

=cut