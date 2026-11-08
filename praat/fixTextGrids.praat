#
# Praat script for correcting SweDia prosody file TextGrids
# Author: Jonathan Jansson <jonathan1jansson@gmail.com>
#

form Automatic correction of SweDia 2000 prosody annotations
	infile: "Sound input directory", ""
	infile: "TextGrid input directory", ""
	outfile: "TextGrid output directory", ""
    comment: "Script will identify the pattern 'A, silence, B'."
    sentence: "Regex A", "(?i(en)$|(fem)$|(tio)$|(hundra)$|(tjugo)$|(femtio)$)"
	positive: "Minimum silence duration (s)", "0.05"
    sentence: "Regex B", "(?i(krona)$|(kronor)$|(dollar)$|(pund)$|(d-mark)$|(mark)$)"
    comment: "Where duration of B is how many tiems greater than A?"
	positive: "Difference factor", "2"
    boolean: "Inspect every file", 1
endform

# Rename some variables from form
soundDirectory$ = sound_input_directory$
tgDirectory$ = textGrid_input_directory$
correctionsDirectory$ = textGrid_output_directory$
diffFactor = difference_factor
minSilenceDuration = minimum_silence_duration

clearinfo
appendInfoLine: "Looking for a difference factor of ", diffFactor, " and minimum silence of ", minSilenceDuration 

inDirTG$ = tgDirectory$ + "*.TextGrid"
tgList = Create Strings as file list: "tgList", inDirTG$
numGrids = Get number of strings
appendInfoLine: "Found ", numGrids, " TextGrids in ", tgDirectory$

for i to numGrids 
	# grids loop
    selectObject: tgList
    gridName$ = Get string: i
	
    # Check if text grid is already in output directory
	if fileReadable: correctionsDirectory$ + gridName$ 
		appendInfoLine: gridName$, " has already been corrected. Skipping."
		goto \%{FULLSKIP}
	endif

	baseName$ = gridName$ - ".TextGrid"
    gridObject = Read from file: tgDirectory$ + gridName$
	soundName$ = baseName$ + ".wav"
	soundPath$ = soundDirectory$ + soundName$

	if not fileReadable: soundPath$
		appendInfoLine: "Found no sound file at ", soundPath$, ". Skipping..."
		goto \%{FULLSKIP}
	else
		soundObject = Read from file: soundPath$
	endif

	# Initialize some variables
	keep = 0
	save = 0
	hasEdited = 0
	hasSkipped = 0
	solution = 0
	noPause = 0
    # This skips manual inspection of each file later 
    if inspect_every_file
        clicked = 0
    else
        clicked = 1
    endif

	# Check if TG follows expected format
	selectObject: gridObject
    isInterval = Is interval tier: 1
		
	if not isInterval
		appendInfoLine: "Tier 1 in ", gridName$, " is not an interval tier. Skipping."
		keep = 0
		goto \%{NEXTGRID}
	endif

	numIntervals = Get number of intervals: 1
	
	if numIntervals < 3
		appendInfoLine: "TextGrid ", gridName$, " contains less than three intervals in tier 1. Keeping textgrid and sound in objects list and skipping."
		Read from file: soundDirectory$ + soundName$
		keep = 1
		goto \%{NEXTGRID}
	endif
	
	# Open and let user inspect
	if inspect_every_file
        selectObject: soundObject
        plusObject: gridObject
        View & Edit
        
        editor: gridObject
            Zoom in
            beginPause: "Inspecting "+gridName$
            comment: "Contains errors? NextFile saves any edits made."
            comment: "File count: " + string$ (i) + "/" + string$ (numGrids)
            clicked = endPause: "Check", "NextFile", "Quit", 1, 3
            Close
        #
    endif
	
	if clicked == 1
		# Check - searched for likely error in this file
	
		# intervals loop. Checks three intervals at a time
		for j to numIntervals - 2  
			selectObject: gridObject
			isMatchA = 0
			isMatchB = 0
			twoAhead$ = ""

			# Check if first interval matches regex A
			rawLabel$ = Get label of interval: 1, j		
			label$ = replace_regex$ (rawLabel$, ".", "\L&", 0)
			isMatchA = index_regex (label$, regex_A$)
			
			if isMatchA
				oneAhead$ = Get label of interval: 1, j+1
				
				if oneAhead$ == ""
					# Next interval is empty, check the interval after that
					rawTwoAhead$ = Get label of interval: 1, j+2
					twoAhead$ = replace_regex$ (rawTwoAhead$, ".", "\L&", 0)
					isMatchB = index_regex (twoAhead$, regex_B$)

					if isMatchB
						# Two intervals ahead matches regex B. Check interval durations.
						aStartTime = Get starting point: 1, j
						aEndTime = Get end point: 1, j
						aDuration = aEndTime - aStartTime
						
						silenceStartTime = Get starting point: 1, j+1
						silenceEndTime = Get end point: 1, j+1
						silenceDuration = silenceEndTime - silenceStartTime
											
						bStartTime = Get starting point: 1, j+2
						startTime$ = string$ (bStartTime)
						bEndTime = Get end point: 1, j+2
						bDuration = bEndTime - bStartTime
						
						if (bDuration >= diffFactor*aDuration) and (silenceDuration >= minSilenceDuration)
							# Error is likely
							if not noPause
								# Open, zoom to selection (or close enough), let user inspect and choose how to proceed
								selectObject: soundObject
								plusObject: gridObject
								View & Edit
								
								editor: gridObject
									Move cursor to: bStartTime
									
									if bDuration <= 1.5
										Move end of selection by: bDuration
									else
										Move end of selection by: 1.5
									endif
									
									Zoom to selection
									Zoom out
									Play or stop

									beginPause: "Inspecting " + gridName$
									comment: "Found likely error for label '" + twoAhead$ + "' starting at " + startTime$
									comment: "'FixFile' corrects all likely errors and lets user inspect results " 
									comment: "'Manually' keeps objects in objects list for manual correction."
									comment: "'NextInt' skips selected interval, saves if end of file is reached."
									comment: "'NextFile' skips TextGrid, copies it as-is and moves on."
									comment: "File count: " + string$ (i) + "/" + string$ (numGrids)
									solution = endPause: "FixFile", "Manually", "NextInt", "NextFile", "Quit", 3, 5
									Close
								#
							endif
	
							if solution == 1
								# FixFile - Try to automatically correct entire file
								noPause = 1
								hasEdited = 1
								save = 1
								selectObject: gridObject
								Set interval text: 1, j+1, rawTwoAhead$
								Set interval text: 1, j+2, ""
								goto \%{NEXTINTERVAL}

							elif solution == 2
								# Manually - Keep in objects list, skip but don't copy
								keep = 1				
								appendInfoLine: gridName$, " will be saved in objects list for manual correction."
								goto \%{NEXTGRID}

							elif solution == 3 ; 
								# NextInt - Skip this interval, but copy file to avoid having to confirm every time script is run
								hasSkipped = 1
								appendInfoLine: "An interval in ", gridName$, " contained no error."
								goto \%{NEXTINTERVAL}
								
							elif solution == 4 ; 
								# NextFile - Skip this file, save
								save = 1
								appendInfoLine: gridName$, " was skipped and saved to output directory."
								goto \%{NEXTGRID}
								
							elif solution == 5 ; Quit script
								removeObject: gridObject
								removeObject: soundObject
								removeObject: tgList
								appendInfoLine: "Script exited by user before ", gridName$
								exitScript ()
							
							endif
		
						endif
					
						#goto \%{NEXTINTERVAL}

					endif
					
				endif
			
			endif
				
			label \%{NEXTINTERVAL}

		endfor
		
	elif clicked = 2
		# Skip - skips without saving
		save = 1
		appendInfoLine: gridName$, " skipped by user."
		
	elif clicked = 3
		# Quit
		removeObject: gridObject
		removeObject: soundObject
		removeObject: tgList
		appendInfoLine: "Script exited by user before ", gridName$
		exitScript ()

	endif

	label \%{NEXTGRID}

	if hasEdited
		# Let user inspect results of automatic correction before saving
		save = 1
		selectObject: gridObject
		plusObject: soundObject
		View & Edit
		
		editor: gridObject
			Move cursor to: bStartTime
			if bDuration <= 1.5
				Move end of selection by: bDuration
			else
				Move end of selection by: 1.5
			endif
			
			Zoom to selection
			Zoom out
			Zoom out
			Zoom out
			Play or stop
			
			beginPause: "Reviewing " + gridName$
			comment: "Last edited interval selected. Save?"
			comment: "File count: " + string$ (i) + "/" + string$ (numGrids)
			clicked = endPause: "OK", "Quit", 1, 2
			
			if clicked == 2
				removeObject: gridObject
				removeObject: soundObject
				removeObject: tgList
				appendInfoLine: "Script exited by user. ", gridName$, " was not saved."
				exitScript ()
			endif
			
			Close
		# Editor closed
	endif

	if hasSkipped
		appendInfoLine: "User skipped last possible error in ", gridName$, "."
		keep = 0	
	endif
	
	selectObject: gridObject
	Save as text file: correctionsDirectory$ + gridName$
	appendInfoLine: gridName$, " was saved to output directory."
	
	if keep == 0
		removeObject: soundObject
		removeObject: gridObject
	endif

	label \%{FULLSKIP}

endfor

removeObject: tgList
appendInfoLine: "Script finished"
