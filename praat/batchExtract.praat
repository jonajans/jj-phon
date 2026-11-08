#
# Praat script for batch extracting parts of SweDia prosody files
# Author: Jonathan Jansson <jonathan1jansson@gmail.com>
#

form SweDia batch-extract
    comment: "Extracts portions from sounds and textgrid based on word accent."
    infile: "TextGrid input directory", ""
    infile: "Sound input directory", ""
    infile: "SweDia metadata csv path", ""
    outfile: "TextGrid output directory", ""
endform

# Rename some variables from form
tgDirectory$ = textGrid_input_directory$
soundDirectory$ = sound_input_directory$
typeFile$ = sweDia_metadata_csv_path$
outDirectory$ = textGrid_output_directory$

inDirTG$ = tgDirectory$ + "*.TextGrid"
tgList = Create Strings as file list: "tgList", inDirTG$
numGrids = Get number of strings
appendInfoLine: "Found ", numGrids, " TextGrids in ", tgDirectory$

if fileReadable: typeFile$
    categoriesFile = Read Table from comma-separated file: typeFile$
else
    appendInfoLine: "Could not read metadata file at ", typeFile, ". Exiting..."
    exitScript("Unable to read metadata file")
endif

csvPath$ = outDirectory$ + "accentCounts_" + speakerType$ + ".csv"

if fileReadable: csvPath$
    pauseScript: "Output file exists. Overwrite?"
endif

writeFileLine: csvPath$, "baseName", tab$, "dialectType", tab$, "accent1f", tab$, "accent1u", tab$, "accent2f", tab$, "accent2u"

for i to numGrids
    selectObject: tgList

	tgName$ = Get string: i
	gridObject = Read from file: tgDirectory$ + "\" + tgName$
	baseName$ = tgName$ - ".TextGrid"
	numIntervals = Get number of intervals: 1
	
    # Get dialect category
	selectObject: categoriesFile
	key$ = left$ (baseName$, 3)
	selectObject: categoriesFile
	lineNum = Search column: "Key", key$

	categoryLong$ = Get value: lineNum, "Type"
	# File sometimes contains two types, so only get the first one
	categoryShort$ = left$ (categoryLong$, 2)	
	
	soundObject = Read from file: soundDirectory$ + "\" + baseName$ + ".wav"

    appendInfoLine: "Extracting from ", baseName$, " of type ", categoryLong$

    # Count accents and focus per file
    a1fCount = 0
    a1uCount = 0
    a2fCount = 0
    a2uCount = 0

    for j to numIntervals
        selectObject: gridObject
        label$ = Get label of interval: 1, j
        lowerLabel$ = replace_regex$ (label$, ".", "\L&", 0)
		
		startTime = 0
		endTime = 0
		
		isNumber = 0
		isNumber = index_regex (lowerLabel$, "(en$)|(fem$)|(tio$)|(tjugo$)|(femtio$)|(hundra$)")
        
        if isNumber
            numberLabel$ = label$

            for k from j + 1 to numIntervals
			
				# if no matching currency found after two intervals, discard number
				#if k >= 3
				#	goto \%{FOUNDCURRENCY}
				#endif
			
                nextLabel$ = Get label of interval: 1, k				
                lowerNextLabel$ = replace_regex$ (nextLabel$, ".", "\L&", 0)
				
				isOtherCurrency = 0
				isOtherCurrency = index_regex (lowerNextLabel$, "(pund$)|(d-mark$)|(mark$)")

				if isOtherCurrency
					# if another currency, just go back to main loop and keep looking
					goto \%{FOUNDCURRENCY}
				endif

                isCurrency = 0
                isCurrency = index_regex (lowerNextLabel$, "(kronor$)|(krona$)|(dollar$)")
				
                if isCurrency
                    currencyLabel$ = nextLabel$
					endTime = Get end point: 1, k

                    if currencyLabel$ == "DOLLAR"
						# if accent 1: extract number + currency
						startTime = Get start point: 1, j
                        a1fCount += 1
                        newName$ = baseName$ + "_ord1f_" + string$ (a1fCount) 

                    elif currencyLabel$ == "dollar"
						startTime = Get start point: 1, j
                        a1uCount += 1   
                        newName$ = baseName$ + "_ord1u_" + string$ (a1uCount) 

                    elif currencyLabel$ == "KRONOR"
						# if accent 2: only extract currency word
						startTime = Get start point: 1, k
                        a2fCount += 1
                        newName$ = baseName$ + "_ord2f_" + string$ (a2fCount) 

                    elif currencyLabel$ == "kronor"
						startTime = Get start point: 1, k
                        a2uCount += 1
                        newName$ = baseName$ + "_ord2u_" + string$ (a2uCount) 

                    endif
					
                    newTG = Extract part: startTime, endTime, "no"

                    selectObject: soundObject
                    newSound = Extract part: startTime, endTime, "rectangular", 1, "no"

                    selectObject: newTG
                    Rename: newName$
					# i.e. 'tg\2A\om\abc_om_ordNx_y.TextGrid'
                    Save as text file: outDirectory$ + "tg\" + categoryShort$ + "\" + speakerType$ + "\" + newName$ + ".TextGrid"

                    selectObject: newSound
                    Rename: newName$
					# i.e. 'sounds\2A\om\abc_om_ordNx_y.wav'
                    Save as WAV file: outDirectory$ + "sounds\" + categoryShort$ + "\" + speakerType$ + "\" + newName$ + ".wav"

                    # Cleanup before moving on
                    removeObject: newTG
                    removeObject: newSound
                    isAccent1f = 0
                    isAccent1u = 0
                    isAccent2f = 0
                    isAccent2u = 0
                    newName$ = ""

                    # keep looping from next interval after currency
                    goto \%{FOUNDCURRENCY}

                endif
                
				label \%{NUM_NEXTINT}
				
            endfor

        endif
		
		label \%{FOUNDCURRENCY}

    endfor

    totalTokens = a1fCount + a1uCount + a2fCount + a2uCount

    appendInfoLine: "Found ", totalTokens, " total currency tokens"

    appendFileLine: csvPath$, baseName$, tab$, categoryShort$, tab$, a1fCount, tab$, a1uCount, tab$, a2fCount, tab$, a2uCount

    removeObject: soundObject
    removeObject: gridObject

endfor

removeObject: tgList
removeObject: categoriesFile

appendInfoLine: "Extraction finished!"
