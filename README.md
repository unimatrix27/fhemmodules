# fhemmodules
Roadmap Snapcast:

attr snap constraintDummy kindOfDay  # im Dummy Kind of Day kann drin stehen was fuer ein Tag ist. Das wirkt als Selektor fuer die Volume Constraints
attr snap configdir <configdir>		 # Directory fuer config files,z.b. fuer Soundschemes, diese werden als Audiofeedback fuer Displaylose Clients genutzt.
attr snap soundpath <sounddir>		 # Directory in dem Sounddateien drin liegen.

set snap volConstraint kind1 beforeSchool 06:30 0 08:00 40 09:00 57 18:00 120 19:00 70 20:00 65 20:30 57 21:20 40 21:30 30 24:00 0
  # wenn im Dummy was bei kindOfDay angegeben wurde der Wert "beforeSchool" drin steht, dann gilt fuer den Client kueche diese Konfig. (hier: ab 21:30 ist schluss mit musik) 
set snap volConstraint kueche 06:30 0 08:00 40 09:00 57 18:00 120 19:00 70 20:00 65 20:30 57 21:20 40 21:30 30 24:00 0
  # globale Konfig, wenn man auf das kindOfDay Zeug verzichten moechte


set snap MPD <stream> <mpdmodul>   #hiermit koennen set commands an MPD weitergereicht werden. 
   Beispiel: set snap play client
   ausserdem neue Kommandos: 
		set snap playlistregexp client <kindname>.*
		set snap playlist client next                  # basierend auf der regexp werden die Playlisten des Kindes durchgeschaltet

	
set snap PAHOST <client> <ip/host>		# Mit PAHOST einen Pulseaudio Hostnamen angeben, ueber den Sound direkt auf dem Client abgespielt werden kann
set snap soundscheme <client> <schemefile>  # ein Soundschema fuer Audiofeedback fuer einen Client festlegen. 


schemefile:
play	dark/blubb.wav
error	dark/error.wav
critical	dark/critical.wav
numbers		dark/numbers/			# fuer numbers muessen eine reihe von files rein, das steht dann in der doku
	# ein basis fileset wuerde ich wohl mitliefern


