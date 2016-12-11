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
    "muted"    => 2,
    "latency"    => 2
);

my %Snapcast_clientmethods = (
    "name"   => "Client.SetName",
    "volume"   => "Client.SetVolume",
    "muted"   => "Client.SetMute",
	"stream"   => "Client.SetStream",
	"latency"   => "Client.SetLatency"
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
    #$hash->{AttrFn}     = 'Snapcast_Attr';
    $hash->{ReadFn}     = 'Snapcast_Read';
    $hash->{TIMEOUT}	= 0.1;
    $hash->{AttrList} =
          "startcmd stopcmd interval "
        . $readingFnAttributes;
	

}

sub Snapcast_Define($$) {
    my ($hash, $def) = @_;
    my @a = split('[ \t]+', $def);
    $hash->{name}  = $a[0];
    $hash->{ip} = (defined($a[2])) ? $a[2] : "localhost"; 
    $hash->{port} = (defined($a[3])) ? $a[3] : "1705"; 
    readingsSingleUpdate($hash,"state","defined",1);
    RemoveInternalTimer($hash);
    DevIo_CloseDev($hash);
    $hash->{DeviceName} = $hash->{ip}.":".$hash->{port};
    DevIo_OpenDev(
            $hash, 0,
            "Snapcast_OnConnect",
        );
    return undef;
}

sub Snapcast_Undef($$) {
    my ($hash, $arg) = @_; 
    RemoveInternalTimer($hash);
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
	
	if(!defined($Snapcast_sets{$opt})) {
		my @cList = keys %Snapcast_sets;
		return "Unknown argument $opt, choose one of " . join(" ", @cList);
	}
	if(@param < $Snapcast_sets{$opt}){
		return "$opt requires at least ".$Snapcast_sets{$opt}." arguments";
	}
	if($opt eq "update"){
		Snapcast_GetStatus($hash);
		return undef;
	}
	if(defined($Snapcast_clientmethods{$opt})){
		my $client = shift @param;
		$client = Snapcast_getMac($hash,$client);
		return "client not found, use unique name, IP, or MAC as client identifier" unless defined($client);
		my $value = shift @param;
		Snapcast_SetClient($hash,$client,$opt,$value);
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
    	fhem "deletereading $name client.*";
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
  		fhem "deletereading ".$name." .*";
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
	if($cnumber==0){
		$cnumber++;
		while(defined($hash->{STATUS}->{clients}->{"$cnumber"}) && $c->{host}->{mac} ne $hash->{STATUS}->{clients}->{"$cnumber"}->{host}->{mac}){$cnumber++}
		if (not defined ($hash->{STATUS}->{clients}->{"$cnumber"})) { 
			Snapcast_GetStatus($hash);
			return undef;
		}
	}
	$hash->{STATUS}->{clients}->{"$cnumber"}=$c;
 	readingsBeginUpdate($hash);
 	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_online",$c->{connected} ? 'true' : 'false' );
 	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_name",$c->{config}->{name} ? $c->{config}->{name} : $c->{host}->{name} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_latency",$c->{config}->{latency} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_stream",$c->{config}->{stream} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_volume",$c->{config}->{volume}->{percent} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_muted",$c->{config}->{volume}->{muted} ? 'true' : 'false' );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_ip",$c->{host}->{ip} );
  	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_mac",$c->{host}->{mac});
  	readingsEndUpdate($hash,1);
}



sub Snapcast_DeleteClient($$$){
	my ($hash,$mac) = @_;
	my $paramset;
	my $cnumber = Snapcast_getClientNumber($hash,$mac);
	return undef unless defined($cnumber);
	my $method="Server.DeleteClient";
	$paramset->{client}=$mac;
	my $result = Snapcast_Do($hash,$method,$paramset);
	return undef unless defined ($result);
	readingsSingleUpdate($hash,"state","Client Deleted: $cnumber",1);
	Snapcast_GetStatus($hash);
}

sub Snapcast_UpdateStream($$$){
	my ($hash,$s,$snumber) = @_;
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
  
  #Log3 $name, 3, Dumper($clients[0]);
  InternalTimer(gettimeofday() + 600, "Snapcast_GetStatus", $hash, 1);
}

sub Snapcast_SetClient($$$$){
	my ($hash,$mac,$param,$value) = @_;
	my $name = $hash->{NAME};
	my $method;
	my $paramset;
	my $cnumber = Snapcast_getClientNumber($hash,$mac);
	Log3 $name,3,"$name $method $mac $param $value $cnumber";
	return undef unless defined($cnumber);
	$paramset->{client}=$mac;
	if(looks_like_number($value)){
		$paramset->{"$param"} = $value+0;
	}else{
		$paramset->{"$param"} = $value
	}

	Log3 $name,3,"$name $method $mac $param $value";
	return undef unless defined($Snapcast_clientmethods{$param});
	$method=$Snapcast_clientmethods{$param};
	Log3 $name,3,"$name $method $mac $param $value";
	my $result = Snapcast_Do($hash,$method,$paramset);
	return undef unless defined ($result);
	readingsBeginUpdate($hash);	
	readingsBulkUpdateIfChanged($hash,"clients_".$cnumber."_".$param,$result->{result} );
	readingsEndUpdate($hash,1);
}

sub Snapcast_Do($$$){
  my ($hash,$method,$param) = @_;
  $param = '' unless defined($param);
  my $line = DevIo_Expect( $hash,Snapcast_Encode($hash,$method,$param),1);
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
  $request->{jsonrpc}="2.0";
  $request->{method}=$method;
  $request->{id}=$hash->{helper}{REQID};
  $request->{params} = $param unless $param eq '';
  Log3 $name,3,encode_json($request)."\r\n";
  return encode_json($request)."\r\n";
}

sub Snapcast_getClientNumber($$){
	my ($hash,$mac) = @_;
	my $name = $hash->{NAME};
	for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
		Log3 $name,3,"MAC: $mac, ".ReadingsVal($name,"clients_".$i."_mac","");
		if ($mac eq ReadingsVal($name,"clients_".$i."_mac","")){
			return $i;
		}
	}
	return undef;
}

sub Snapcast_getMac($$){
	my ($hash,$client) = @_;
	my $name = $hash->{NAME};
	if($client=~/^([0-9a-f]{2}([:-]|$)){6}$/i){ # client is already a MAC
		return $client;
	}
	if($client =~ qr/^(?!(\.))(\.?(\d{1,3})(?(?{$^N > 255})(*FAIL))){4}$/){ # client is given as IP address
		for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
			if ($client eq ReadingsVal($name,"clients_".$i."_ip","")){
				return ReadingsVal($name,"clients_".$i."_mac","");
			}
		}
	}
	for(my $i=1;$i<=ReadingsVal($name,"clients",1);$i++){
		if ($client eq ReadingsVal($name,"clients_".$i."_name","")){
			return ReadingsVal($name,"clients_".$i."_mac","");
		}
	}
}


1;

=pod
=begin html

<a name="Snapcast"></a>
<h3>Snapcast</h3>
<ul>
    <i>PASeerver</i> is the server side module for the FHEM Pulseaudio Multiroom Solution. It automates the process of managing
	the dynamic creation and deletion of Pulseaudio Tunnel and Combine Sinks in order to create a truly synced multiroom audiio experience
	Pulseaudio capable of transfering audio to any other computer running Pulseaudio, and also to more than one at once. Snapcast integrates this capability
	into FHEM and combined with the PAClient module it enables the FHEM user to have several clients listen to different or the same source of audio in sync or independently on demand
	The Snapcast is only useful if there is at least one PAClient while the multiroom feature is only useable with at least 2 clients obviously.
	Direct playback on the server is not yet implemented
    <br><br>
    <a name="Snapcastdefine"></a>
    <b>Define</b>
    <ul>
        <code>define <name> Snapcast <ip></code>
        <br><br>
        Example: <code>define MyServer Snapcast 127.0.0.1</code>
        <br><br>
        The ip parameter gives the hostname or ip of the machine where pulseaudio is running on and where the audio source is going to be played
		Currently the Snapcast and PAClient framework is work in progress. It is planned to directly integrate with the mpd sound server using the FHEM MPD module.
        See <a href="http://fhem.de/commandref.html#define">commandref#define</a> 
        for more info about the define command.
    </ul>
    <br>
    
    <a name="Snapcastset"></a>
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