#
# Praat script for measuring word accent falls on pitch tier files in a directory
# Author: Jonathan Jansson <jonathan1jansson@gmail.com>
#

form Measuring word accent fall in F0 stylizations
	infile: "PitchTier input directory", ""
	infile: "Syllable segmentation input directory", ""
	infile: "Word level annotation input directory", ""
	comment: "Results are saved to tab-separated .csv file in script directory."
	comment: "NB: currently only works for 2A-dialects. Word accent is determined from file name."
endform

ptDirectory$ = pitchTier_input_directory$
prosogram_tgDirectory$ = syllable_segmentation_input_directory$
swedia_tgDirectory$ = word_level_annotation_input_directory$

# if user forgot to finish directories with slashes:
if not right$ (ptDirectory$, 1) == "\"
	ptDirectory$ = ptDirectory$ + "\"
endif

if not right$ (prosogram_tgDirectory$, 1) == "\"
	prosogram_tgDirectory$ = prosogram_tgDirectory$ + "\"
endif

if not right$ (swedia_tgDirectory$, 1) == "\"
	swedia_tgDirectory$ = swedia_tgDirectory$ + "\"
endif

outFile$ = "F0falls_master.csv"

# Check if output file exists, ask if before creating
if fileReadable: outFile$
    pauseScript: "Output file exists. Overwrite?"
endif

writeInfoLine: "Saving results to ", outFile$

inDirPitch$ = ptDirectory$ + "*.PitchTier"
pitchList = Create Strings as file list: "pitchList", inDirPitch$
numPitch = Get number of strings
appendInfoLine: "Found ", numPitch, " PitchTier files in ", ptDirectory$ 

headerRow$ = "fileName" + tab$ + "accent" + tab$ + "focus" + tab$ + "startPitch" + tab$ + "endPitch" + tab$ + "dPitch" + tab$ + "startST" + tab$ + "endST" + tab$ + "dST" + tab$ + "startTime" + tab$ + "endTime" + tab$ + "dTime" + tab$ + "glissandoThreshold" + tab$ + "glissRatio" + tab$ + "aboveGT"
writeFileLine: outFile$, headerRow$

# pitchtier loop
for i to numPitch
	isMatch = 0	
	currency_startTime = 0
	currency_endTime = 0
	postCurrency_endTime = 0
	postStressSyll_endTime = 0
	preStressSyll_startTime = 0
	maxIndex = 0
	minIndex = 0

    selectObject: pitchList
    pitchName$ = Get string: i
    ptObject = Read from file: ptDirectory$ + "\" + pitchName$
    baseName$ = pitchName$ - "_styl.PitchTier"
		
	if mid$ (pitchName$, 14, 1) == "1"
		accentType = 1
	elif mid$ (pitchName$, 14, 1) == "2"
		accentType = 2
	else
		appendInfoLine: "Could not determine accent type of ", pitchName$, ". Tried to process: ", left$ (pitchName$, 14), ". Script exited."
		exitScript: "Error. Check info window!"
	endif
	
	if mid$ (pitchName$, 15, 1) == "f"
		focus = 1
	elif mid$ (pitchName$, 15, 1) == "u"
		focus = 0
	else
		appendInfoLine: "Could not determine whether ", pitchName$, " is focused or not. Tried to process: ", left$ (pitchName$, 15), ". Script exited."
		exitScript: "Error. Check info window!"		
	endif
	
	if accentType = 1
		# Find starting point of number annotation
		
		swedia_tgPath$ = swedia_tgDirectory$ + baseName$ + ".TextGrid"
		
		if not fileReadable: swedia_tgPath$
			appendInfoLine: "Unable to read ", swedia_tgPath$, " Skipping..."
			goto \%{NEXTFILE}
		else
			swediaGrid = Read from file: swedia_tgPath$
		endif
		
		numInts = Get number of intervals: 1
		
		if numInts < 2
			appendInfoLine: "Found ", numInts, "intervals in tier 1 of ", swedia_tgPath$, " but expected at least 2. Skipping..."
			goto \%{NEXTFILE}
		else
			
			for j from 1 to numInts
				label$ = Get label of interval: 1, j
				lowerLabel$ = replace_regex$ (label$, ".", "\L&", 0)
				
				if index_regex (lowerLabel$, "(dollar)$|(pund)$")
					isMatch = 1
					swedia_startTime = Get starting point: 1, j
				endif
			endfor
		
			removeObject: swediaGrid

		endif

		if not isMatch
			appendInfoLine: baseName$, ".TextGrid had no number in tier 1. Skipping..."
			goto \%{NEXTFILE}
		endif
						
		# at this point, index and timestamps of number have been found
		# use prosogram syllable segmentation to find the starting time of syllable before number
		
		prosogram_tgPath$ = prosogram_tgDirectory$ + baseName$ + "_nucl.TextGrid"
		
		if not fileReadable: prosogram_tgPath$
			appendInfoLine: "Unable to read ", prosogram_tgPath$, " Skipping..."
			goto \%{NEXTFILE}
		else
			prosogramGrid = Read from file: prosogram_tgPath$
		endif
		
		# Tier 4 contains prosogram's approximate syllable segmentation
		numInts = Get number of intervals: 4
		
		if numInts < 2
			appendInfoLine: "Found ", numInts, "intervals in tier 1 of ", prosogram_tgPath$, " but expected at least 2. Skipping..."
			goto \%{NEXTFILE}

		else
			# Find which interval in prosogram textgrid overlaps or matches currency interval in swedia textgrid
			# This is needed because Swedia annotation is inconsistent, and to account for things like hesitation
			
			if swedia_startTime == 0
				preStressSyll_startTime = 0
			else
				for k from 1 to numInts
					pg_startTime = Get starting point: 4, k
					pg_endTime = Get end point: 4, k
					
					if (pg_startTime <= swedia_startTime) and (swedia_startTime <= pg_endTime)						
						# if possible, we want the syllable BEFORE as this is the point the fall should start (Bruce 1977: 48-49)
						# but the prosogram segmentation is approximate and may not have identified all syllables

						if k > 1
							# If there is a preceeding syllable:
							preStressSyll_startTime = Get starting point: 4, k-1
							currency_endTime = Get end point: 4, k
						endif
											
					endif
					
				endfor

				label \%{FOUND_SYLLAFTER}
				
			endif
			
			
		endif
		
		removeObject: prosogramGrid

		# Now, the script has identified a starting point for measurements on the pitch tier stylizations
		selectObject: ptObject
		
		# Determine closest point to start and end of interval
		startIndex = Get nearest index from time: preStressSyll_startTime
		endIndex = Get nearest index from time: currency_endTime			
		
		if endIndex <= startIndex
			appendInfoLine: "Start and end index for ", baseName$, " are equal: ", startIndex, " and ", endIndex, ". Skipping..."
			goto \%{NEXTFILE}
		endif
		
		# First, find F0 maximum among indices
		maxPitch = Get value at index: startIndex
		maxTime = Get time from index: startIndex
		maxIndex = startIndex
		
		# range needs to be reduced by 1 to make sure more than one point is captured
		for l from startIndex to endIndex - 1
		
			thisPitch = Get value at index: l
			
			if thisPitch > maxPitch
				maxPitch = thisPitch
				maxIndex = l
				maxTime = Get time from index: l
			endif
		
		endfor
				
		maxST = 12*log2(maxPitch)
		
		# Then, find F0 minimum between maximum and end index
		if (endIndex + 1) - maxIndex < 2
			appendInfoLine: "Warning: too small range of indeces (", (endIndex + 1) - maxIndex, ") would be used to check F0-minimum in ", baseName$, ". Skipping..."
			goto \%{NEXTFILE}
		endif
		
		minPitch = maxPitch
		lastPitch = maxPitch

		for n from maxIndex to endIndex + 1
			
			thisPitch = Get value at index: n
			
			if thisPitch < minPitch
				minPitch = thisPitch
				minIndex = n
				minTime = Get time from index: n
			endif
			
			if thisPitch > lastPitch
				minPitch = lastPitch
				minIndex = n
				minTime = Get time from index: n
				goto \%{A1_FOUND_TTP}
			else
				lastPitch = thisPitch
			endif
			
		endfor
		
		# Check if F0 continues to fall after last index, in which case that pitch should be saved as min instead
		currency_endPitch = Get value at time: currency_endTime
		if currency_endPitch < minPitch
			minPitch = currency_endPitch
			appendInfoLine: "F0 fall continued after reaching last index without finding TTP in ", baseName$
			minTime = currency_endTime
		endif

		label \%{A1_FOUND_TTP}

		# The script has now found the index with the lowest pitch in the post-stress syllable.
		# Make remaining calculations
		minST = 12*log2(minPitch)
		dPitch = maxPitch - minPitch

		if dPitch == 0
			appendInfoLine: "No word accent fall found in stylization of ", baseName$, ". Skipping..."
			goto \%{NEXTFILE}
		endif
			
		dST = maxST - minST
		dTime = minTime - maxTime
		
		if dTime <= 0
			appendInfoLine: "dTime is negative in ", baseName$, "! Looked for maxPitch between ", startIndex, " and ", endIndex - 1, ", and minPitch between ", maxIndex, " and ", endIndex + 1, ". Skipping..."
			goto \%{NEXTFILE}
		endif
		
		# Check if fall is above GT
		gTR = 0.16/(dTime^2)
		glissQ = dST / (dTime^2)
		
		if glissQ > gTR
			aboveGT$ = "dynamic"
		else
			aboveGT$ = "static"
		endif
		
	elif accentType = 2
		# For accent 2, just find and measure first fall
		
		prosogram_tgPath$ = prosogram_tgDirectory$ + baseName$ + "_nucl.TextGrid"
		
		if not fileReadable: prosogram_tgPath$
			appendInfoLine: "Unable to read ", prosogram_tgPath$, " Skipping..."
			goto \%{NEXTFILE}
		else
			prosogramGrid = Read from file: prosogram_tgPath$
		endif

		numInts = Get number of intervals: 4

		for j to numInts
			
			label$ = Get label of interval: 4, j
			
			# the first syllable in "kronor" has the word accent, but there may be empty intervals before
			# this determines possible range for f0 peak
			if label$ == "syl"
				currency_startTime = Get starting point: 4, j
				currency_endTime = Get end point: 4, j
				currencyInterval = j
				goto \%{FOUND_ACCENTSYLL}
			endif
		
		endfor
		
		label \%{FOUND_ACCENTSYLL}
		
		# this determines end range of possible f0 minimum (again, loop used to account for possible empty intervals)
		for k from j to numInts
		
			if label$ == "syl"
				postStressSyll_endTime = Get end point: 4, k
				goto \%{FOUND_POSTACCENTSYLL}
			endif
			
		endfor
		
		label \%{FOUND_POSTACCENTSYLL}
		
		removeObject: prosogramGrid
		
		# determine indices of the above ranges in pitch tier file
		selectObject: ptObject

		possibleMax_startIndex = Get nearest index from time: currency_startTime

		# Using nearest index often lead to errors, and there is no hope of measuring a fall if the range is only one interval (hence -1)
		possibleMax_endIndex = Get nearest index from time: currency_endTime
		possibleMin_endIndex = Get nearest index from time: postStressSyll_endTime
		
		if (possibleMin_endIndex + 1) - maxIndex < 2
			appendInfoLine: "Warning: too small range of indeces (", (possibleMin_endIndex + 1) - maxIndex, ") would be used to check F0-minimum in ", baseName$, ". Skipping..."
			goto \%{NEXTFILE}

		endif

		maxPitch = Get value at index: possibleMax_startIndex
		maxTime = Get time from index: possibleMax_startIndex
		maxIndex = possibleMax_startIndex

		for l from possibleMax_startIndex to possibleMax_endIndex - 1
			thisPitch = Get value at index: l
			
			if thisPitch > maxPitch
				maxPitch = thisPitch
				maxIndex = l
				maxTime = Get time from index: l

			endif
		
		endfor
						
		maxST = 12*log2(maxPitch)
		
		# Then, find F0 TTP between maximum and end index
		lastPitch = maxPitch
		minPitch = maxPitch

		for m from maxIndex to possibleMin_endIndex + 1
			thisPitch = Get value at index: m

			# This if condition stores minimum F0 pitch 
			if thisPitch < minPitch
				minPitch = thisPitch
				minIndex = m
				minTime = Get time from index: m

			endif
			
			if thisPitch > lastPitch
				minPitch = lastPitch
				minIndex = m
				minTime = Get time from index: m
				goto \%{A2_FOUND_TTP}

			else
				lastPitch = thisPitch

			endif
			
		endfor
		
		# Here, check if F0 continues to fall after last index, in which case we should save that pitch as min instead
		postStress_endPitch = Get value at time: postStressSyll_endTime
		if postStress_endPitch < minPitch
			minPitch = postStress_endPitch
			minTime = postStressSyll_endTime
			appendInfoLine: "F0 continued to fall after reaching last index without finding TTP in ", baseName$

		endif
		
		label \%{A2_FOUND_TTP}
		
		# After this loop, the script has found the index with the lowest pitch in the post-stress syllable.
		# Make remaining calculations
		minST = 12*log2(minPitch)
		dPitch = maxPitch - minPitch
		
		if dPitch == 0
			appendInfoLine: "No word accent fall found in stylization of ", baseName$, ". Skipping..."
			goto \%{NEXTFILE}

		endif
		
		dST = maxST - minST
		dTime = minTime - maxTime
		
		if dTime <= 0
			appendInfoLine: "dTime is negative in ", baseName$, "! Looked for maxPitch between ", startIndex, " and ", endIndex - 1, ", and minPitch between ", maxIndex, " and ", endIndex + 1, ". Skipping..."
			goto \%{NEXTFILE}

		endif
		
		# Check if fall is above GT
		gTR = 0.16/(dTime^2)
		glissQ = dST / (dTime^2)
		
		if glissQ > gTR
			aboveGT$ = "dynamic"
		else
			aboveGT$ = "static"
		endif

	else
		appendInfoLine: "Could not determine word accent from filename: ", pitchName$, ". Skipping..."
		goto \%{NEXTFILE}

	endif
	
	# Write results
	# headerRow$: "fileName" + ""accent" + "focus" + "startPitch" + "endPitch" + "dPitch" + "startST" + "endST" + "dST" + "startTime" + "endTime" + "dTime" + gTR + glissQ + aboveGT$
	appendFileLine: outFile$, baseName$, tab$, accentType, tab$, focus, tab$, maxPitch, tab$, minPitch, tab$, dPitch, tab$, maxST, tab$, minST, tab$, dST, tab$, maxTime, tab$, minTime, tab$, dTime, tab$, gTR, tab$, glissQ, tab$, aboveGT$

	label \%{NEXTFILE}
	removeObject: ptObject

endfor

removeObject: pitchList
appendInfoLine: "Script finished"
