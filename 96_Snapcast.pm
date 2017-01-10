package main;
use strict;
use warnings;
use Scalar::Util qw(looks_like_number);

my $Snapcast_LogLevelDebug = 1;
my $Snapcast_LogLevelNormal = 1;
my $Snapcast_LogLevelCritical =1;


my %Snapcast_gets = (
	"tbd"	=> "x"
);

my %Snapcast_sets = (
    "update"   => 0,
    "volume"   => 2,
    "stream"   => 2,
    "name"	   => 2,
    "mute"    => 2,
    "latency"    => 2,
);

my %Snapcast_client_sets = (
    "volume"   => 1,
    "stream"   => 1,
    "name"     => 1,
    "mute"    => 1,
    "latency"    => 1,
);


my %Snapcast_clientmethods = (
    "name"   => "Client.SetName",
    "volume"   => "Client.SetVolume",
    "mute"   => "Client.SetMute",
	"stream"   => "Client.SetStream",
	"latency"   => "Client.SetLatency",
	"volumeConstraint" => "internal"
);


sub Snapcast_Initialize($) {
    my ($hash) = @_;
	require "$attr{global}{modpath}/FHEM/DevIo.pm";
    $hash->{DefFn}      = 'Snapcast_Define';
    $hash->{UndefFn}    = 'Snapcast_Undef';
    $hash->{SetFn}      = 'Snapcast_Set';
    $hash->{GetFn}      = 'Snapcast_Get';
	$hash->{WriteFn}    = 'Snapcast_Write';
	$hash->{ReadyFn}    = 'Snapcast_Ready';
    $hash->{AttrFn}     = 'Snapcast_Attr';
    $hash->{ReadFn}     = 'Snapcast_Read';
    $hash->{TIMEOUT}	= 0.1;
    $hash->{AttrList} =
          "streamnext:all,playing constraintDummy volumeStepSize "
        . $readingFnAttributes;
}

sub Snapcast_Define($$) {
    my ($hash, $def) = @_;
    my @a = split('[ \t]+', $def);
    return "ERROR: perl module JSON is not installed" if (Snapcast_isPmInstalled($hash,"JSON"));
    my $name= $hash->{name}  = $a[0];
    if($a[2] eq "client"){
        return "Usage: define <name> Snapcast client <server> <id>" unless (defined($a[3]) && defined($a[4]));
        return "Server $a[3] not defined" unless defined ($defs{$a[3]});
        $hash->{MODE} = "client";
        $hash->{SERVER} = $a[3];
        $hash->{ID} = $a[4];
        readingsSingleUpdate($hash,"state","defined",1);
        RemoveInternalTimer($hash);
        DevIo_CloseDev($hash);
        $attr{$name}{volumeStepSize}       = '5'      unless (exists($attr{$name}{volumeStepSize}));
        return Snapcast_Client_Register_Server($hash);
    }
    $hash->{ip} = (defined($a[2])) ? $a[2] : "localhost"; 
    $hash->{port} = (defined($a[3])) ? $a[3] : "1705"; 
    $hash->{MODE} = "server";
    readingsSingleUpdate($hash,"state","defined",1);
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    $hash->{DeviceName} = $hash->{ip}.":".$hash->{port};
    $attr{$name}{volumeStepSize}       = '5'      unless (exists($attr{$name}{volumeStepSize}));
    DevIo_OpenDev(
            $hash, 0,
            "Snapcast_OnConnect",
        );
    return undef;
}

sub Snapcast_Attr($$){
	my ($cmd, $name, $attr, $value) = @_;
    my $hash = $defs{$name};
	if($attr eq "streamnext"){	
			return "streamnext needs to be either all or playing" unless $value=~/(all)|(playing)/;
	}
  if($attr eq "volumeStepSize"){
    return "volumeStepSize needs to be a number between 1 and 100" unless $value>0 && $value <=100;
  }
	return undef;
}

sub Snapcast_Undef($$) {
    my ($hash, $arg) = @_; 
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    if($hash->{MODE} eq "client"){
      Snapcast_Client_Unregister_Server($hash);
    }
    return undef;
}


sub Snapcast_Get($@) {
	my ($hash, @param) = @_;
	return '"get Snapcast" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	if(!$Snapcast_gets{$opt}) {
		my @cList = keys %Snapcast_gets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	return "to be defined";  
}

sub Snapcast_Set($@) {
	my ($hash, @param) = @_;
	
	return '"set Snapcast" needs at least one argument' if (int(@param) < 2);
	
	my $name = shift @param;
	my $opt = shift @param;
	my $value = join(" ", @param);
  my %sets = ($hash->{MODE} eq "client") ? %Snapcast_client_sets : %Snapcast_sets;


	if(!defined($sets{$opt})) {
    my @cList = keys %sets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	if(@param < $sets{$opt}){
		return "$opt requires at least ".$sets{$opt}." arguments";
	}
	if($opt eq "update"){
		Snapcast_GetStatus($hash);
		return undef;
	}
	if(defined($Snapcast_clientmethods{$opt})){
    my $client;
    if($hash->{MODE} eq "client"){
      my $clientmod=$hash;
      $client=$hash->{NAME};
      $hash=$hash->{SERVER};
      $hash=$defs{$hash};
      $client=$clientmod->{ID};
      return "Cannot find Server hash" unless defined ($hash);
    }else{
      $client = shift @param;
      $client = Snapcast_getId($hash,$client) unless $client eq "all";
    }
		$value = join(" ", @param);
		return "client not found, use unique name, IP, or MAC as client identifier" unless defined($client);
		if($client eq "all"){
			for(my $i=1;$i<=ReadingsVal($name,"clients",0);$i++){
				my $res = Snapcast_SetClient($hash,ReadingsVal($name,"clients_".$i."_id",""),$opt,$value);
				readingsSingleUpdate($hash,"lastError",$res,1) if defined ($res);
      }
			return undef;
		}
		Log3 $name,3,"SetClient $hash, $client, $opt, $value";
    my $res = Snapcast_SetClient($hash,$client,$opt,$value);
		readingsSingleUpdate($hash,"lastError",$res,1) if defined ($res);
		return undef;
	}


	return "$opt not yet implemented $value";
}

sub Snapcast_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $buf;
  
  $buf = DevIo_SimpleRead($hash);
    return "" if ( !defined($buf) );
  $buf = $hash->{PARTIAL} . $buf;
  
  my $lastchr = substr( $buf, -1, 1 );
  if ( $lastchr ne "\n" ) {
      $hash->{PARTIAL} = $buf;
      Log3( $hash, 5, "snap: partial command received" );
      return;
  }
  else {
      $hash->{PARTIAL} = "";
  }

  my @lines = split( "\n", $buf );
  foreach my $line (@lines) {
    # Hier die Results parsen
    Log3 $name, 3, $line;
    my $update=decode_json($line);
    if($update->{method}=~/Client\.OnDelete/){
    	my $s=$update->{params}->{data};
    	fhem "deletereading $name clients.*";
    	Snapcast_GetStatus($hash);
    	return undef;
    }
    if($update->{method}=~/Client\./){
    	my $c=$update->{params}->{data};
    	Snapcast_UpdateClient($hash,$c,0);
    	return undef;
    }
    if($update->{method}=~/Stream\./){
    	my $s=$update->{params}->{data};
    	Snapcast_UpdateStream($hash,$s,0);
    	return undef;
    }

  }
}


sub Snapcast_Ready($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  if (AttrVal($hash->{NAME}, 'disable', 0)) {
    return;
  }
  if ( ReadingsVal( $name, "state", "disconnected" ) eq "disconnected" ) {
  		fhem "deletereading ".$name." streams.*";
  		fhem "deletereading ".$name." clients.*";
        DevIo_OpenDev($hash, 1,"Snapcast_OnConnect");
        return;
    }

  return undef;
}

sub Snapcast_OnConnect($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  $hash->{LAST_CONNECT} = FmtDateTime( gettimeofday() );
  $hash->{CONNECTS}++;
  $hash->{helper}{PARTIAL} = "";
  Snapcast_GetStatus($hash);
  return undef;
 }

sub Snapcast_UpdateClient($$$){
	my ($hash,$c,$cnumber) = @_;
  my $name = $hash->{NAME};
	if($cnumber==0){
		$cnumber++;
		while(defined($hash->{STATUS}->{clients}->{"$cnumber"}) && $c->{host}->{mac} ne $hash->{STATUS}->{clients}->{"$cnumber"}->{host}->{mac}){$cnumber++}
		if (not defined ($hash->{STATUS}->{clients}->{"$cnumber"})) { 
			Snapcast_GetStatus($hash);
			return undef;
		}
	}
	$hash->{STATUS}->{clients}->{"$cnumber"}=$c;
  my $id=$c->{id}? $c->{id} : $c->{host}->{mac};    # protocol version 2 has no id, but just the MAC, newer versions will have an ID. 
  $id=~s/\://g;
 	readingsBeginUpdate($hash);
 	  readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_online",$c->{connected} ? 'true' : 'false' );
 	  readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_name",$c->{config}->{name} ? $c->{config}->{name} : $c->{host}->{name} );
    readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_latency",$c->{config}->{latency} );
    readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_stream",$c->{config}->{stream} );
    readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_volume",$c->{config}->{volume}->{percent} );
    readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_muted",$c->{config}->{volume}->{muted} ? 'true' : 'false' );
    readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_ip",$c->{host}->{ip} );
    readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_mac",$c->{host}->{mac});
    readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_id",$id);

    readingsBulkUpdateIfChanged($hash,"clients_".$id."_online",$c->{connected} ? 'true' : 'false' );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_name",$c->{config}->{name} ? $c->{config}->{name} : $c->{host}->{name} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_latency",$c->{config}->{latency} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_stream",$c->{config}->{stream} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_volume",$c->{config}->{volume}->{percent} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_muted",$c->{config}->{volume}->{muted} ? 'true' : 'false' );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_ip",$c->{host}->{ip} );
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_mac",$c->{host}->{mac}); 
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_id",$id); 
    readingsBulkUpdateIfChanged($hash,"clients_".$id."_nr",$cnumber); 
  readingsEndUpdate($hash,1);
  my $clientmodule = $hash->{$id};
  my $clienthash=$defs{$clientmodule};
  return undef unless defined ($clienthash);
  readingsBeginUpdate($clienthash);
    readingsBulkUpdateIfChanged($clienthash,"online",$c->{connected} ? 'true' : 'false' );
    readingsBulkUpdateIfChanged($clienthash,"name",$c->{config}->{name} ? $c->{config}->{name} : $c->{host}->{name} );
    readingsBulkUpdateIfChanged($clienthash,"latency",$c->{config}->{latency} );
    readingsBulkUpdateIfChanged($clienthash,"stream",$c->{config}->{stream} );
    readingsBulkUpdateIfChanged($clienthash,"volume",$c->{config}->{volume}->{percent} );
    readingsBulkUpdateIfChanged($clienthash,"muted",$c->{config}->{volume}->{muted} ? 'true' : 'false' );
    readingsBulkUpdateIfChanged($clienthash,"ip",$c->{host}->{ip} );
    readingsBulkUpdateIfChanged($clienthash,"mac",$c->{host}->{mac}); 
    readingsBulkUpdateIfChanged($clienthash,"id",$id); 
  readingsEndUpdate($clienthash,1);
  return undef;
}



sub Snapcast_DeleteClient($$$){
	my ($hash,$id) = @_;
  my $name = $hash->{NAME};
	my $paramset;
  my $cnumber = ReadingsVal($name,"clients_".$id."_nr","");
	return undef unless defined($cnumber);
	my $method="Server.DeleteClient";
	$paramset->{client}=ReadingsVal($hash,"clients_".$id."_mac","");
	my $result = Snapcast_Do($hash,$method,$paramset);
	return undef unless defined ($result);
	readingsSingleUpdate($hash,"state","Client Deleted: $cnumber",1);
	Snapcast_GetStatus($hash);
}

sub Snapcast_UpdateStream($$$){
	my ($hash,$s,$snumber) = @_;
  my $name = $hash->{NAME};
	if($snumber==0){
		$snumber++;
		while(defined($hash->{STATUS}->{streams}->{"$snumber"}) && $s->{id} ne $hash->{STATUS}->{streams}->{"$snumber"}->{id}){$snumber++}
		if (not defined ($hash->{STATUS}->{streams}->{"$snumber"})){ return undef;}
	}
	$hash->{STATUS}->{streams}->{"$snumber"}=$s;
 	readingsBeginUpdate($hash);	
 	readingsBulkUpdateIfChanged($hash,"streams_".$snumber."_id",$s->{id} );
	readingsBulkUpdateIfChanged($hash,"streams_".$snumber."_status",$s->{status} );
  readingsEndUpdate($hash,1);
}

sub Snapcast_Client_Register_Server($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return undef unless $hash->{MODE} eq "client";
  my $server = $hash->{SERVER};
  if (not defined ($defs{$server})){
    InternalTimer(gettimeofday() + 30, "Snapcast_Client_Check_Server", $hash, 1); # if server does not exists maybe it got deleted, recheck every 30 seconds if it reappears
    return undef;
  }
  my $id=$hash->{ID};
  $server = $defs{$server}; # get the server hash
  return undef unless defined($server);
  $server->{$id} = $name;
  Snapcast_GetStatus($server);
  return undef;
}

sub Snapcast_Client_Unregister_Server($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  return undef unless $hash->{MODE} eq "client";
  my $server = $hash->{SERVER};
  return undef if (not defined ($defs{$server}));
  my $id=$hash->{ID};
  $server = $defs{$server}; # get the server hash
  return undef unless defined($server);
  readingsSingleUpdate($server,"clients_".$id."_module",$name,1 );
  delete($server->{$id});
  return undef;
}

sub Snapcast_GetStatus($){
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  my $status=Snapcast_Do($hash,"Server.GetStatus",'');
  return undef unless defined ($status);
  my $streams=$status->{result}->{streams};
  my $clients=$status->{result}->{clients};
  my $server=$status->{result}->{server};

  
  $hash->{STATUS}->{server}=$server;
  if(defined ($clients)){
  	my @clients=@{$clients};
  	my $cnumber=1;
  	foreach my $c(@clients){
	  	Snapcast_UpdateClient($hash,$c,$cnumber);
	  	$cnumber++;
  	}
  	readingsBeginUpdate($hash);	
    readingsBulkUpdateIfChanged($hash,"clients",$cnumber-1 );
    readingsEndUpdate($hash,1);
  }
  if(defined ($streams)){
  	my @streams=@{$streams} unless not defined ($streams);
  	my $snumber=1;
  	foreach my $s(@streams){
	  	Snapcast_UpdateStream($hash,$s,$snumber);
	  	$snumber++;
  	}
  	readingsBeginUpdate($hash);	
  	readingsBulkUpdateIfChanged($hash,"streams",$snumber-1 );
  	readingsEndUpdate($hash,1);
  }
    InternalTimer(gettimeofday() + 600, "Snapcast_GetStatus", $hash, 1); # every 10 minutes the complete status is updated to be on the safe side
}

sub Snapcast_SetClient($$$$){
	my ($hash,$id,$param,$value) = @_;
	my $name = $hash->{NAME};
	my $method;
	my $paramset;
	my $cnumber = ReadingsVal($name,"clients_".$id."_nr","");
	return undef unless defined($cnumber);
	$paramset->{client}=ReadingsVal($name,"clients_".$id."_mac","");
	return undef unless defined($Snapcast_clientmethods{$param});
	$method=$Snapcast_clientmethods{$param};
	if($param eq "volumeConstraint"){
		my @values=split(/ /,$value);
		my $match;
		return "not enough parameters for volumeConstraint" unless @values>=2;
		if(@values%2){ # there is a match argument given because number is uneven
			$match=pop(@values);
		}else{$match="_global_"}
		for(my $i=0;$i<@values;$i+=2){
			return "wrong timeformat 00:00 - 24:00 for time/volume pair" unless $values[$i]=~/^(([0-1]?[0-9]|2[0-3]):[0-5][0-9])|24:00$/;
			return "wrong volumeformat 0 - 100 for time/volume pair" unless $values[$i+1]=~/^(0?[0-9]?[0-9]|100)$/;
		}
		#readingsSingleUpdate($hash,"volumeConstraint_".$mac."_".$match,$value,1);
		return undef;
	}
	if($param eq "stream"){
		$param="id";
		if($value eq "next"){ # just switch to the next stream, if last stream, jump to first one. This way streams can be cycled with a button press
			my $totalstreams=ReadingsVal($name,"streams","");
			my $currentstream = ReadingsVal($name,"clients_".$cnumber."_stream","");
			$currentstream = Snapcast_getStreamNumber($hash,$currentstream);
			
			my $newstream = $currentstream+1;
			$newstream=1 unless $newstream <= $totalstreams;
			while(AttrVal($name, 'streamnext', 'all') eq 'playing' && ReadingsVal($name,"streams_".$newstream."_status","") ne "playing" && $newstream!=$currentstream ) {
				$newstream++;
				$newstream=1 unless $newstream <= $totalstreams;
			}
			$value=ReadingsVal($name,"streams_".$newstream."_id","");
		}
	}
  # check if volume was given as increment or decrement, then find out current volume and calculate new volume
  if($param eq "volume" && $value=~/^([\+\-])(\d{1,2})$/){
    my $direction = $1;
    my $amount = $2;
    my $currentVol = ReadingsVal($name,"clients_".$id."_volume","");
    return undef unless defined($currentVol);
    if($direction eq "+"){$value = $currentVol + $amount;}else{$value = $currentVol - $amount;}
    $value = 100 if ($value >= 100);
    $value = 0 if ($value <0);
  }
  # if volume is given with up or down argument, then increase or decrease according to volumeStepSize
  if($param eq "volume" && $value=~/^(up|down)$/){
    my $currentVol = ReadingsVal($name,"clients_".$id."_volume","");
    return undef unless defined($currentVol);
    my $step=AttrVal($name,"volumeStepSize",5);
    if ($value eq "up"){$value = $currentVol + $step;}else{$value = $currentVol - $step;}
    $value = 100 if ($value >= 100);
    $value = 0 if ($value <0);
  }
	if(looks_like_number($value)){
		$paramset->{"$param"} = $value+0;
	}else{
		$paramset->{"$param"} = $value
	}
	my $result = Snapcast_Do($hash,$method,$paramset);
	return undef unless defined ($result);
	$param=~s/id/stream/;
	readingsBeginUpdate($hash);	
	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_".$param,$result->{result} );
  readingsBulkUpdateIfChanged($hash,"clients_".$id."_".$param,$result->{result} );
	readingsEndUpdate($hash,1);
  my $clientmodule = $hash->{$id};
  my $clienthash=$defs{$clientmodule};
  return undef unless defined ($clienthash);
  readingsBeginUpdate($clienthash);
  readingsBulkUpdateIfChanged($clienthash,$param,$result->{result} );
  readingsEndUpdate($clienthash,1);
}



sub Snapcast_Do($$$){
  my ($hash,$method,$param) = @_;
  $param = '' unless defined($param);
  my $line = DevIo_Expect( $hash,Snapcast_Encode($hash,$method,$param),1);
  return undef unless defined($line);
  if($line=~/error/){
  	readingsSingleUpdate($hash,"lastError",$line,1);
  	return undef;
  }
  return decode_json($line);
}

sub Snapcast_Encode($$$){
  my ($hash,$method,$param) = @_;
  my $name = $hash->{NAME};
  if(defined($hash->{helper}{REQID})){$hash->{helper}{REQID}++;}else{$hash->{helper}{REQID}=1;}
  my $request;
  my $json;
  $request->{jsonrpc}="2.0";
  $request->{method}=$method;
  $request->{id}=$hash->{helper}{REQID};
  $request->{params} = $param unless $param eq '';
  Log3 $name,3,encode_json($request)."\r\n";
  $json=encode_json($request)."\r\n";
  $json =~s/\"true\"/true/;			# Snapcast needs bool values without "" but encode_json does not do this
  $json =~s/\"false\"/false/;
  return $json;
}

sub Snapcast_getStreamNumber($$){
	my ($hash,$id) = @_;
	my $name = $hash->{NAME};
	for(my $i=1;$i<=ReadingsVal($name,"streams",1);$i++){
		if ($id eq ReadingsVal($name,"streams_".$i."_id","")){
			return $i;
		}
	}
	return undef;
}


sub Snapcast_getId($$){
	my ($hash,$client) = @_;
	my $name = $hash->{NAME};
	if($client=~/^([0-9a-f]{2}([:-]|$)){6}$/i){ # client is already a MAC
		for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
      if ($client eq ReadingsVal($name,"clients_".$i."_mac","")){
        return ReadingsVal($name,"clients_".$i."_id","");
      }
    }
	}
	if($client =~ qr/^(?!(\.))(\.?(\d{1,3})(?(?{$^N > 255})(*FAIL))){4}$/){ # client is given as IP address
		for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
			if ($client eq ReadingsVal($name,"clients_".$i."_ip","")){
				return ReadingsVal($name,"clients_".$i."_id","");
			}
		}
	}
	for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
		if ($client eq ReadingsVal($name,"clients_".$i."_name","")){
			return ReadingsVal($name,"clients_".$i."_id","");
		}
	}
}

sub Snapcast_isPmInstalled($$)
{
  my ($hash,$pm) = @_;
  my ($name,$type) = ($hash->{NAME},$hash->{TYPE});
  if (not eval "use $pm;1")
  {
    Log3 $name, 1, "$type $name: perl modul missing: $pm. Install it, please.";
    return "failed: $pm";
  }
  
  return undef;
}
1;

=pod
=item summary    control and monitor Snapcast Server
=begin html

<a name="Snapcast"></a>
<h3>Snapcast</h3>
<ul>
    <i>Snapcast</i> is a module to control a Snapcast Server. Snapcast is a little project to achieve multiroom audio and is a leightweight alternative to such solutions using Pulseaudio.
    Find all information about Snapcast, how to install and configure on the <a href="https://github.com/badaix/snapcast">Snapcast GIT</a>. To use this module, the minimum is to define a snapcast server module
    which defines the connection to the actual snapcast server. See the define section for how to do this. On top of that, it is possible to define virtual client modules, so that each snapcast client that is connected to 
    the Snapcast Server is represented by its own FHEM module. The purpose of that is to provide an interface to the user that enables to integrate Snapcast Clients into existing visualization solutions and to use 
    other FHEM capabilities around it, e.g. Notifies, etc. The server module includes all readings of all snapcast clients, and it allows to control all functions of all snapcast clients. 
    Each virtual client module just gets the reading for the specific client. The client modules is encouraged and also makes it possible to do per-client Attribute settings, e.g. volume step size and volume constraints. 
    <br><br>
    <a name="Snapcastdefine"></a>
    <b>Define</b>
    <ul>
        <code>define <name> Snapcast [&lt;ip&gt; &lt;port&gt;]</code>
        <br><br>
        Example: <code>define MySnap Snapcast 127.0.0.1 1705</code>
        <br><br>
        This way a snapcast server module is defined. IP defaults to localhost, and Port to 1705, in case you run Snapcast in the default configuration on the same server as FHEM, you dont need to give those parameters.
        <br><br><br>
        <code>define <name> Snapcast client &lt;server&gt; &lt;clientid&gt;</code>
         <br><br>
        Example: <code>define MySnapClient Snapcast client MySnap aabbccddeeff</code>
        <br><br>
        This way a snapcast client module is defined. The keyword client does this. The next argument links the client module to the associated server module. The final argument is the client ID. In Snapcast each client gets a unique ID,
         which is normally made out of the MAC address. Once the server module is initialized it will have all the client IDs in the readings, so you want to use those for the definition of the client modules
    </ul>
    <br>
    <a name="Snapcastset"></a>
    <b>Set</b><br>
    <ul>
        For a Server module: <code>set &lt;name&gt; &lt;function&gt; &lt;client&gt; &lt;value&gt;</code>
        <br><br>
        For a Client module: <code>set &lt;name&gt; &lt;function&gt; &lt;value&gt;</code>
        <br><br>
        Options:
        <ul>
              <li><i>update</i><br>
                  Perform a full update of the Snapcast Status including streams and servers. Only needed if something is not working</li>
              <li><i>volume</i><br>
                  Set the volume of a client. For this and all the following 4 options, give client as second parameter (only for the server module), either as name, IP , or MAC and the desired value as third parameter. 
                  Client can be given as "all", in that case all clients are changed at once (only for server module)<br>
                  Volume cna be given in 3 ways: Range betwee 0 and 100 to set volume directly. Increment or Decrement given between -100 and +100. Keywords <em>up</em> and <em>down</em> to increase or decrease with a predifined step size. 
                  The step size can be defined in the attribute <em>volumeStepSize</em></li>
              <li><i>mute</i><br>
                  Mute or unmute by giving "true" or "false" as value. Use "toggle" to toggle between muted and unmuted.</li>
              <li><i>latency</i><br>
                  Change the Latency Setting of the client</li>
              <li><i>name</i><br>
                  Change the Name of the client</li>
              <li><i>stream</i><br>
                  Change the stream that the client is listening to. Snapcast uses one or more streams which can be unterstood as virtual audio channels. Each client/room can subscribe to one of them. 
                  By using next as value, you can cycle through the avaialble streams</li>
        </ul>
</ul>
 <br><br>
  <a name="Snapcastattr"></a>
  <b>Attributes</b>
  <ul>
    <li>streamnext</li>All attributes can be set to the master module and the client modules. Using them for client modules enable the setting of different attribute values per client. 
    <li>streamnext<br>
    Can be set to <i>all</i> or <i>playing</i>. If set to <i>all</i>, the <i>next</i> function cycles through all streams, if set to <i>playing</i>, the next function cycles only through streams in the playing state.
    </li>
    <li>volumeStepSize<br>
      Default: 5. Set this to define, how far the volume is changed when using up/down volume commands. 
    </li>
        <li>constraintDummy<br>
    Links the Snapcast module to a dummy. The value of the dummy is then used as a selector for different sets of volumeConstraints. See the description of the volumeConstraint command.
    </li>
  </ul>
</ul>

=end html

=currentstream