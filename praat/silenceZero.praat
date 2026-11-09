form Automatic silence of non-annotated intervals
    comment: "For each empty interval in TextGrids in the following directory, this script silences the same part of the corresponding wav file (at nearest zero-crossings)"
	comment: ""
	positive: "Shortest interval duration to set to zero (s)", "0.1"
	infile: "Sound input directory", "/"
	infile: "Sound output directory", "/silenced/"
	outfile: "Reference textgrid directory", "/cor_tg/"
	boolean: "Verbose interval skipping", 0
endform

# Initialize variables
minDur = shortest_interval_duration_to_set_to_zero
soundDirectory$ = sound_input_directory$
silencedDirectory$ = sound_output_directory$
tgDirectory$ = reference_textgrid_directory$
verbSkipping = verbose_interval_skipping

# Read TextGrids
inDirTG$ = tgDirectory$ + "*.TextGrid"
tgList = Create Strings as file list: "tgList", inDirTG$
numGrids = Get number of strings
appendInfoLine: "Found ", numGrids, " TextGrids in ", tgDirectory$


for i to numGrids 
    selectObject: tgList
    gridName$ = Get string: i
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

	# Check if TG follows expected format
	selectObject: gridObject
    isInterval = Is interval tier: 1
	
    # Initialize variables
    keep = 0

	if not isInterval
		appendInfoLine: "Tier 1 in ", gridName$, " is not an interval tier. Skipping file."
		keep = 0
		goto \%{NEXTFILE}
	endif

	numIntervals = Get number of intervals: 1
	
	if numIntervals < 3
		appendInfoLine: "TextGrid ", gridName$, " contains less than three intervals in tier 1. Keeping textgrid and sound in objects list and skipping."
		Read from file: soundDirectory$ + soundName$
		keep = 1
		goto \%{NEXTFILE}
	endif

	silencedName$ = baseName$ + "_silenced.wav"
	
    for j to numIntervals
        selectObject: gridObject
        intvStart = Get start point: 1, j
        intvEnd = Get end point: 1, j
		intvDur = intvEnd - intvStart
		intvLabel$ = Get label of interval: 1, j

		# skip non-empty intervals
		if intvLabel$ != ""
			if verbSkipping
				appendInfoLine: "Skipping interval #", j, " in textgrid ", baseName$, " with label ", intvLabel$, "."
			endif
			goto \%{NEXTINTV}
		endif

		if intvDur < minDur
			if verbSkipping
				appendInfoLine: "Skipping interval #", j, " in textgrid ", baseName$, " which had duration ", intvDur, " s." 
			endif
			goto \%{NEXTINTV}
		endif

        selectObject: soundObject
		startZero = Get nearest zero crossing: 1, intvStart
        endZero = Get nearest zero crossing: 1, intvEnd
		zeroDur = endZero - startZero

        View & Edit

        editor: soundObject
            Move cursor to: startZero
			Move end of selection by: zeroDur
			Set selection to zero
			Close
		endeditor
		
		label \%{NEXTINTV}

    endfor            

	selectObject: soundObject
	Save as WAV file: silencedDirectory$ + silencedName$
	appendInfoLine: silencedName$, " was saved to output directory."

	label \%{NEXTFILE}

	removeObject: soundObject

	label \%{FULLSKIP}

	removeObject: gridObject

endfor

removeObject: tgList
appendInfoLine: "Done"