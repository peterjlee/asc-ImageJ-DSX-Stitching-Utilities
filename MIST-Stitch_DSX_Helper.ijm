/* Autorecognize parameters for and runs MIST stitching on a file directory of DSX images.
	MIST references:
	T. Blattner et. al. "A Hybrid CPU-GPU System for Stitching of Large Scale Optical Microscopy Images", 2014 International Conference on Parallel Processing, 2014. https://doi.org/10.1109/ICPP.2014.9
	J. Chalfoun, et al. "MIST: Accurate and Scalable Microscopy Image Stitching Tool with Stage Modeling and Error Minimization". Scientific Reports. 2017;7:4988. https://doi.org/10.1038/s41598-017-04567-y
	
	This macro requires that the exifReader plugin has previously been installed: https://imagej.net/plugins/exif-reader.html

	v230201: 1st version   Peter J. Lee  Applied Superconductivity Center  NHMFL FSU
	v230202: Adds more option including just stitching a limited number of initial tiles (useful for checking overlap).
	v230203-8: 1st version using MIST plugin - generally more successful for DSX mosaics
	v230215-6: Saves some settings in user preferences file. Tries to better handle situations where no DSX panorama files are found.
	v230220: Removed stray text and renamed function: getDSXPanoFilesWithSameExtension.
	v230310: The path for the generated parameter file is now copied to the clipboard to make it easier to open in MIST.
	v230315: Multiple sets fixed.
	v230404-v230420: 1st Dialog skipped if there is only one map set. Unused variables removed. NaNs converted to ""
	v230516: Allows for aspected pixels.
	v230608: Updated getExifData function so it can search for the last index value. Removed confusing directory dialog.
	v230616: Replaced getInfo with getExifData function so that overlap is imported.
	v230803: Replaced getDir for 1.54g10. F1: Updated indexOfArray functions. F2: Updated sensibleUnits function and removed now-redundant indexOfArray function.
	v240223: Dialog tweaks.
	v240225: Missing path1 corrected.
	v240226: Added closeOriginal options.
	v240227: Headless mode now working!!
	v240301: Autosave option changed from multi-channel OME to RGB tif. Global position file path saving fixed.
	v240304: Fixed closeOriginal Dialog error;
	v240311: Fix for calcRepeatability not having NaN default setting. Sub-grids fixed. Paths with spaces fixed for headless mode. fftw plans saved in image sub-folder as they are unique/image. More unique naming of files for testing different parameters.
	v240312: Shortens menu by 2 lines.
 */
	macroL = "MIST-Stitch_DSX_Helper_v240312.ijm";
	prefsNameKey = "asc.MIST.Stitch.Helper.Prefs.";
	orImageID = getImageID();
	fileName = getInfo("image.filename");
	fWOE = File.getNameWithoutExtension(fileName);
	ext = substring(fileName, fWOE.length+1);
	dir = getInfo("image.directory");
	// allowableFormats = newArray("dsx", "tif", "png", "jpeg");
	foundDSXMapFiles = getDSXPanoFilesWithSameExtension(dir, ext);
	if (foundDSXMapFiles.length<1) exit("No tiles were found");
	path1 = dir + foundDSXMapFiles[0];
	dsxEXIFData = getExifData(path1);
	tileCount = foundDSXMapFiles.length;
	if (tileCount<2) exit("Only found " + tileCount + "files; that is not enough to create a panorama");
	imageWidth = Image.width;
	imageHeight = Image.height;
	dirF = substring(dir, 0, dir.length-1);
	micronS = getInfo("micrometer.abbreviation");
	fS = File.separator();
	bits = bitDepth();
	win = startsWith(getInfo("os.name"), "Windows");
	calcRepeatability = NaN;
	if (toLowerCase(ext)=="dsx"){
		umPerPixelX = parseInt(getDSXExifTagFromMetaData(dsxEXIFData, "ColorDataPerPixelX", true)) * 10E-7;
		umPerPixelY = parseInt(getDSXExifTagFromMetaData(dsxEXIFData, "ColorDataPerPixelY", true)) * 10E-7;
		umPerPixelOrX = parseInt(getDSXExifTagFromMetaData(dsxEXIFData, "ImageDataPerPixelX", true)) * 10E-7;
		umPerPixelOrY = parseInt(getDSXExifTagFromMetaData(dsxEXIFData, "ImageDataPerPixelY", true)) * 10E-7;
		if (umPerPixelX!=umPerPixelOrX) IJ.log("Note that for " + path1 + " the stored output X scale \(" + umPerPixelX + " microns per pixel\) was different from the original acquisition scale \(" + umPerPixelOrX + " microns per pixel\). The output scale is used.");
		aspectRatio = umPerPixelX/umPerPixelY;
		run("Set Scale...", "distance=1 known="+umPerPixelX+" pixel="+aspectRatio+" unit=um");
		IJ.log("Pixel size set from DSX image header: " +umPerPixelX+ " " + micronS + ", Aspect ratio: " + aspectRatio);
		/* DSX scale will only be as saved from Olympus app, so no modifications will be necessary */
		pixelW = umPerPixelX;
		pixelH = umPerPixelY;
		unit = micronS;
	}
	else getVoxelSize(pixelW, pixelH, voxelDepth, unit);
	if(unit!="pixels"){
		newPixelWidthNewUnits = sensibleUnits(pixelW, unit);
		pixelW = newPixelWidthNewUnits[0];
		unit = newPixelWidthNewUnits[1];
		newPixelHeightNewUnits = sensibleUnits(pixelH, unit);
		pixelH = newPixelHeightNewUnits[0];
	}
	//Array.print(foundDSXMapFiles);
	mapSets = getUniqueElementPrefixes(foundDSXMapFiles, "_X");
	mapSetsL = mapSets.length;
	gridWidth = 0; gridHeight = 0;
	if(mapSetsL==0) exit("No DSX Mosaic files found");
	else if(mapSetsL==1) prefixF = mapSets[0];
	else {
		Dialog.create("Set Options \(" + macroL + "\)");
			Dialog.addMessage("Total DSX mosaic files in directory = " + tileCount, 10, "black");
			Dialog.addRadioButtonGroup("Choose map set:", mapSets, 2, round(mapSetsL/2), mapSets[0]);
			tileListMessage = "";
			for (i=0;i<mapSetsL;i++){
				tileListMessage += mapSets[i] + ": total tiles in set: " + countArrayElementsWithString(foundDSXMapFiles, mapSets[i]);
				if(i+1<mapSetsL) tileListMessage += "\n";
			} 
			Dialog.addMessage(tileListMessage);
		Dialog.show();
			prefixF = Dialog.getRadioButton();
	}
	suffixF = "." + ext;
	filteredDSXMapFiles = newArray();
	for (i=0, fTC=0;i<tileCount;i++){
		imageT = foundDSXMapFiles[i];
		if(startsWith(imageT, prefixF)){
			filteredDSXMapFiles[fTC] = imageT;
			if (fTC==0){
				pSX =  lastIndexOf(imageT, "_X") + 2;
				pSY =  lastIndexOf(imageT, "_Y") + 2;
				digitN = abs(pSY-pSX) - 2;
			}
			xN = parseInt(substring(imageT, pSX, pSX+digitN));
			yN = parseInt(substring(imageT, pSY, pSY+digitN));
			if (fTC==0){
				startTileCol = xN;
				lastTileCol = xN;
				startTileRow = yN;
				lastTileRow = yN;
			}
			else{
				startTileCol = minOf(startTileCol, xN);
				lastTileCol = maxOf(lastTileCol, xN);
				startTileRow = minOf(startTileRow, yN);
				lastTileRow = maxOf(lastTileRow, yN);
			}
		fTC++;
		}
	}
	gridWidth = lastTileCol - startTileCol + 1;
	gridHeight = lastTileRow - startTileRow + 1;
	lastParamPath = call("ij.Prefs.get", prefsNameKey+"paramPath", "");
	if (lastParamPath!=""){
		lastLogPath = replace(lastParamPath, "Params", "log");
		if (File.exists(lastLogPath)){
			lastLog = File.openAsString(lastLogPath);
			iForNorth = indexOf(lastLog, "for North: ") + 11;
			if (iForNorth>=0){
				iNextPixels = indexOf(lastLog, " pixels", iForNorth);
				if (iNextPixels>=0 && iForNorth>iNextPixels){
					repeatNorth = d2s(substring(lastLog, iForNorth, iNextPixels), 0);
					call("ij.Prefs.set", prefsNameKey+"repeatNorth", repeatNorth);				
				}
				else iNextPixels = 0;
			}
			else iNextPixels = 0;
			iForWest = indexOf(lastLog, "for West: ", iNextPixels) + 10;
			if (iForWest>=0){
				iNextPixels = indexOf(lastLog, " pixels", iForWest);
				if (iNextPixels>=0 && iForWest>iNextPixels){
					repeatWest = d2s(substring(lastLog, iForWest, iNextPixels), 0);
					call("ij.Prefs.set", prefsNameKey+"repeatWest", repeatWest);
				}
				else iNextPixels = 0;
			}
			else iNextPixels = 0;
			iCalcRepeatability = indexOf(lastLog, "Calculated Repeatability: ", iNextPixels) + 26;
			if (iCalcRepeatability>=0){
				iNextPixels = indexOf(lastLog, " pixels", iCalcRepeatability);
				if (iNextPixels>iCalcRepeatability){
					calcRepeatability = d2s(substring(lastLog, iCalcRepeatability, iNextPixels), 0);
					call("ij.Prefs.set", prefsNameKey+"calcRepeatability", calcRepeatability);				
				}
			}		
		}
	}
	/* ASC Dialog style */
	infoColor = "#006db0"; /* Honolulu blue */
	instructionColor = "#798541"; /* green_dark_modern (121, 133, 65) AKA Wasabi */
	infoWarningColor = "#ff69b4"; /* pink_modern AKA hot pink */
	infoFontSize = 12;
	Dialog.create("Options for Params File \(" + macroL + "\)");
		Dialog.addHelp("https://github.com/usnistgov/MIST/wiki/Combined-User-Install-Guide#input-parameters");
		if (screenHeight>800) Dialog.addMessage("Total DSX mosaic files in set = " + fTC + ". Full grid is " + gridWidth + " x " + gridHeight + ". You can define a sub-grid below to test parameters:", infoFontSize, infoColor);
		Dialog.addNumber("Subgrid start row", 1, 0, 4, "1 - " + gridHeight + " \(relative to 1st row available\)");
		Dialog.addNumber("Subgrid start column:", 1, 0, 4, "1 - " + gridWidth + " \(relative to 1st column available\)");
		Dialog.addNumber("Subgrid rows:", gridHeight, 0, 4, "1 - " + gridHeight);
		Dialog.addNumber("Subgrid columns:", gridWidth, 0, 4, "1 - " +  gridWidth);
		Dialog.addString("Input parent directory: ", dirF, Math.constrain(0.9 * dirF.length, 61, 120));
		Dialog.addString("Output parent directory: ", dirF, Math.constrain(0.9 * dirF.length, 61, 120));
		horizontalOverlap = parseInt(getDSXExifTagFromMetaData(dsxEXIFData, "OverlapSize", true));
		if (horizontalOverlap<=0) horizontalOverlap = call("ij.Prefs.get", prefsNameKey+"horizontalOverlap", 20);
		Dialog.addNumber("Horizontal overlap", NaN, 0, 5, "% \(best left blank for new calculation\), embedded value=" + horizontalOverlap);
		if (horizontalOverlap<=0) verticalOverlap = call("ij.Prefs.get", prefsNameKey+"horizontalOverlap", 20);
		else verticalOverlap = horizontalOverlap;
		Dialog.addNumber("Vertical overlap", NaN, 0, 3, "% \(best left blank for new calculation\), embedded value=" + verticalOverlap);
		overlapUncertainty = call("ij.Prefs.get", prefsNameKey+"overlapUncertainty", 3);
		Dialog.addNumber("Overlap uncertainty", overlapUncertainty, NaN, 6, "% \(increasing to 10% or more may help\)");
		stageRepeatability = call("ij.Prefs.get", prefsNameKey+"stageRepeatability", 87);
		calcWest = call("ij.Prefs.get", prefsNameKey+"repeatWest", NaN);
		calcNorth = call("ij.Prefs.get", prefsNameKey+"repeatNorth", NaN);
		cReptText = "pixels, leave blank to compute new";
		if (!isNaN(calcRepeatability)) cReptText +=  " \(previous calculated: West=" + calcWest + ", North=" + calcNorth + "\)";
		Dialog.addNumber("Stage Repeatability", NaN, 0, 3, cReptText);
		outputOptions1 = newArray("Display stitching", "Auto-save ...tif", "Output meta", "Output image pyramid");
		outputOptionsD1s = split(call("ij.Prefs.get", prefsNameKey+"outputOptionsD1", "1|1|1|0"), "|");
		Dialog.setInsets(10, 20, 0);
		Dialog.addCheckboxGroup(1, outputOptions1.length, outputOptions1, outputOptionsD1s); /* Output options */
		blendingOptions = newArray("Overlay", "Linear", "Average");
		blendingMode = toSentenceCase(call("ij.Prefs.get", prefsNameKey+"blendingMode", blendingOptions[1]));
		blendingLabel = "Blending options:";
		if(bits==24) blendingLabel += "   \(RGB images may cause out of memory issues for linear and average blending\)";
		Dialog.addRadioButtonGroup(blendingLabel, blendingOptions, 1, blendingOptions.length, blendingMode);
		blendingHelp = "Overlay: 1 pixel chosen from overlapping pixels based on highest accuracy";
		blendingHelp += "\nLinear: Smoothly blends intensity over overlapping areas. Smoothness controlled by 'Alpha' below.";
		blendingHelp += "\nAverage: Computes the average intensity.   Note: Linear looks best but can hide issues";
		if (screenHeight>800){
			Dialog.setInsets(-5, 20, 0);
			Dialog.addMessage(blendingHelp, infoFontSize, infoColor);
		} 
		blendingAlpha = call("ij.Prefs.get", prefsNameKey+"blendingAlpha", 5);
		Dialog.addNumber("Alpha:", blendingAlpha, 0, 1, "for Linear and Average blending \(from 0 to 10, 5 usually good enough\)");
		transRefinements = newArray("Single_hill_climb", "Multi_point_hill_climb", "Exhaustive");
		transRefinement = toSentenceCase(call("ij.Prefs.get", prefsNameKey+"transRefinement", transRefinements[1]));
		Dialog.setInsets(-5, 20, 0);
		Dialog.addRadioButtonGroup("Translation refinements: \(left-to-right: fast-to-slow, try 'Single' 1st, it might just work\)", transRefinements, 1, transRefinements.length, transRefinement);
		transRefinementsPts = call("ij.Prefs.get", prefsNameKey+"transRefinementsPts ", minOf(imageWidth, imageHeight)/12);
		Dialog.setInsets(5, 0, 3);
		Dialog.addNumber("Translation refinement", transRefinementsPts, 0, 2, "start points \(16 default but larger numbers help\)");
		cpuThreads = call("ij.Prefs.get", prefsNameKey+"cpuThreads", 0);
		Dialog.addNumber("CPU threads:", 0, 0, 3, "to limit to \('0' uses all\)");
		numFFTPeaks = call("ij.Prefs.get", prefsNameKey+"numFFTPeaks", 8);
		Dialog.addNumber("FFT Peaks:", numFFTPeaks, 0, 1, "0-10 range \(default 2, 8 slow but reliable on difficult sets\)");
		fftwPlanTypes = newArray("Measure", "Patient", "Exhaustive");
		fftwPlanType = toSentenceCase(call("ij.Prefs.get", prefsNameKey+"fftwPlanType", fftwPlanTypes[0]));
		Dialog.addRadioButtonGroup("FFTW Plan Type \('Measure' is usually good enough\):", fftwPlanTypes, 1, fftwPlanTypes.length, fftwPlanType);
		useDoublePrecision = call("ij.Prefs.get", prefsNameKey+"useDoublePrecision", true);
		if (fileName.length>23) shortOriginalFileName = substring(fileName, 0, 10) + "..." + substring(fileName, fileName.length - 10);
		else shortOriginalFileName = fileName;
		finalOptions = newArray("FFT Double Precision Math?", "Headless process* \(doesn't open MIST window\)", "Diagnostics mode?");
		finalChecks = newArray(useDoublePrecision, true, call("ij.Prefs.get", prefsNameKey+"diagnostics", false));
		if (endsWith(fileName, "dsx")){
			finalOptions = Array.concat(finalOptions, "Close '" + shortOriginalFileName + "' on finish");
			finalChecks = Array.concat(finalChecks, call("ij.Prefs.get", prefsNameKey + "closeOriginal", false));
		}
		Dialog.setInsets(10, 20, 0);
		Dialog.addCheckboxGroup(2, Math.ceil(finalOptions.length/2), finalOptions, finalChecks);
		if (screenHeight>1000){
			Dialog.setInsets(0, 20, -10);
			Dialog.addMessage("* If 'Headless mode' is not chosen, the MIST parameter file must be manually loaded into MIST\n  The 'params' file path is copied to the system clipboard but can also be copied from the log window", infoFontSize + 1, instructionColor);
			Dialog.addMessage("           Stitching can take a long time; look for 'Done' in the log file for completion", infoFontSize + 1, infoWarningColor);
		}
	Dialog.show();
		startRow = Math.constrain(Dialog.getNumber(), 1, gridHeight)-1;
		startCol = Math.constrain(Dialog.getNumber(), 1, gridWidth)-1;
		extentHeight = Math.constrain(Dialog.getNumber(), 1, gridHeight);
		extentWidth = Math.constrain(Dialog.getNumber(), 1, gridWidth);
		inDir = Dialog.getString();
		outDir = Dialog.getString();
		horizontalOverlap = minOf(90, Dialog.getNumber());
		call("ij.Prefs.set", prefsNameKey+"horizontalOverlap", horizontalOverlap);
		verticalOverlap = minOf(90, Dialog.getNumber());
		call("ij.Prefs.set", prefsNameKey+"verticalOverlap", verticalOverlap);
		overlapUncertainty = Dialog.getNumber();
		call("ij.Prefs.set", prefsNameKey+"overlapUncertainty", overlapUncertainty);
		stageRepeatability = round(Dialog.getNumber());
		call("ij.Prefs.set", prefsNameKey+"stageRepeatability", stageRepeatability);
		if (isNaN(stageRepeatability) || stageRepeatability<1 || stageRepeatability>2147483647) stageRepeatability = 0;
		displayStitching = Dialog.getCheckbox();
		autosaveRGB_Tiff = Dialog.getCheckbox();
		outputMeta = Dialog.getCheckbox();
		outputImgPyramid = Dialog.getCheckbox();
		call("ij.Prefs.set", prefsNameKey+"outputOptionsD1", displayStitching+"|"+autosaveRGB_Tiff+"|"+outputMeta+"|"+outputImgPyramid);
		blendingMode = toUpperCase(Dialog.getRadioButton());
		call("ij.Prefs.set", prefsNameKey+"blendingMode", ""+blendingMode);
		blendingAlpha = Math.constrain(Dialog.getNumber(), 0, 10);
		call("ij.Prefs.set", prefsNameKey+"blendingAlpha", blendingAlpha);
		transRefinement = toUpperCase(Dialog.getRadioButton());
		call("ij.Prefs.set", prefsNameKey+"transRefinement", ""+transRefinement);
		transRefinementsPts = parseInt(Dialog.getNumber());
		call("ij.Prefs.set", prefsNameKey+"transRefinementsPts", ""+transRefinementsPts);
		numFFTPeaks = parseInt(Dialog.getNumber());
		call("ij.Prefs.set", prefsNameKey+"numFFTPeaks", numFFTPeaks);
		cpuThreads = Dialog.getNumber();
		call("ij.Prefs.set", prefsNameKey+"cpuThreads", cpuThreads);
		fftwPlanType = toUpperCase(Dialog.getRadioButton());
		call("ij.Prefs.set", prefsNameKey+"fftwPlanType", ""+fftwPlanType);
		useDoublePrecision = Dialog.getCheckbox();
		call("ij.Prefs.set", prefsNameKey+"useDoublePrecision", useDoublePrecision);
		headlessMode = Dialog.getCheckbox();
		diagnostics = Dialog.getCheckbox();
		call("ij.Prefs.set", prefsNameKey+"diagnostics", diagnostics);
		if (endsWith(fileName, "dsx")){
			closeOriginal = Dialog.getCheckbox();
			call("ij.Prefs.set", prefsNameKey + "closeOriginal", closeOriginal);
		}
		else closeOriginal = false;
	if (headlessMode && (extentHeight * extentWidth) > fTC) exit("There is only a subset of the files in this directory; Select a subset or use the non-headless mode"); 
	setBatchMode(true);
	if (!File.isDirectory(outDir)) File.makeDirectory(outDir);
	colDes = "";
	rowDes = "";
	for(i=0;i<digitN;i++){
		colDes += "c";
		rowDes += "r";
	}
	fPattern = prefixF + "_X{"+colDes+"}_Y{"+rowDes+"}" + suffixF; /* pattern used by DSX1000 */
	outFilePrefix = prefixF + "_MIST-"; /*MIST will add 'stitched-0.ome.tif' to the end of this */
	ijDir = getDirectory("imagej");
	fftwDir = ijDir + "lib" + fS + "fftw";
	fftwPlanDir = outDir + fS + "fftwPlans";
	if (!File.exists(fftwPlanDir)) File.makeDirectory(fftwPlanDir);
	if(unit==micronS || unit=="um" || unit=="microns") mistUnit = "MICROMETER";
	else if (unit=="nm") mistUnit = "NANOMETER";
	else if (unit=="mm") mistUnit = "MILLIMETER";
	else if (unit=="pm") mistUnit = "PICOMETER";
	else exit("Try a different unit");
	/* Params that can be saved */
	paramsTxt = "gridWidth: " + gridWidth + "\n";
	paramsTxt += "gridHeight: " +  gridHeight + "\n";
	paramsTxt += "startTileRow: " +  startTileRow + "\n";
	paramsTxt += "startTileCol: " + startTileCol + "\n";
	paramsTxt += "imageDir: " + inDir + "\n";
	paramsTxt += "filenamePattern: " + fPattern + "\n";
	paramsTxt += "filenamePatternType: ROWCOL\n";
	paramsTxt += "gridOrigin: UL\n";
	paramsTxt += "numberingPattern: HORIZONTALCOMBING\n";
	paramsTxt += "assembleFromMetadata: false\n";
	paramsTxt += "assembleNoOverlap: false\n";
	paramsTxt += "globalPositionsFile: \n";
	paramsTxt += "startRow: " + startRow + "\n";
	paramsTxt += "startCol: " + startCol + "\n";
	paramsTxt += "extentWidth: " + extentWidth + "\n";
	paramsTxt += "extentHeight: " + extentHeight + "\n";
	paramsTxt += "timeSlices: 0\n";
	paramsTxt += "isTimeSlicesEnabled: false\n";
	paramsTxt += "outputPath: " + outDir + "\n";
	paramsTxt += "displayStitching: " + checkToText(displayStitching) + "\n";
	paramsTxt += "outputFullImage: false\n";
	paramsTxt += "outputMeta: " + checkToText(outputMeta) + "\n";
	paramsTxt += "outputImgPyramid: " + checkToText(outputImgPyramid) + "\n";
	paramsTxt += "blendingMode: " + blendingMode + "\n";
	paramsTxt += "blendingAlpha: " + d2s(blendingAlpha, 1) + "\n";
	paramsTxt += "compressionMode: LZW\n";
	paramsTxt += "outFilePrefix: " + outFilePrefix + "\n";
	paramsTxt += "unit: " + mistUnit + "\n";
	paramsTxt += "unitX: " + pixelW + "\n";
	paramsTxt += "unitY: " + pixelH + "\n";
	paramsTxt += "programType: AUTO\n";
	if (cpuThreads>0){
		numCPUsStr = "numcputhreads=" + d2s(cpuThreads, 0);
		paramsTxt += "numCPUThreads: " + cpuThreads + "\n";
	}
	else numCPUsStr = "";
	paramsTxt += "loadFFTWPlan: true\n";
	paramsTxt += "saveFFTWPlan: true\n";
	paramsTxt += "fftwPlanType: " + fftwPlanType + "\n";;
	paramsTxt += "fftwLibraryName: libfftw3\n";
	paramsTxt += "fftwLibraryFilename: libfftw3.dll\n";
	paramsTxt += "planPath: " + fftwPlanDir + "\n";
	paramsTxt += "fftwLibraryPath: " + fftwDir + "\n";
	paramsTxt += "stageRepeatability: " + stageRepeatability + "\n";
	paramsTxt += "horizontalOverlap: " + horizontalOverlap + "\n";
	paramsTxt += "verticalOverlap: " + verticalOverlap + "\n";
	paramsTxt += "numFFTPeaks: " + numFFTPeaks + "\n";
	paramsTxt += "overlapUncertainty: " + d2s(overlapUncertainty, 1) + "\n";
	paramsTxt += "isUseDoublePrecision: " + checkToText(useDoublePrecision) + "\n";
	paramsTxt += "isUseBioFormats: false\n";
	paramsTxt += "isSuppressModelWarningDialog: false\n";
	paramsTxt += "isEnableCudaExceptions: false\n"; /* CUDA is no loner supported in MIST */
	paramsTxt += "translationRefinementMethod: " + transRefinement + "\n";
	paramsTxt += "numTranslationRefinementStartPoints: " + transRefinementsPts + "\n";
	paramsTxt += "headless: false\n";
	paramsTxt += "logLevel: HELPFUL\n";
	paramsTxt += "debugLevel: HELPFUL";
	// paramsTxt = replace(paramsTxt, "NaN", "");	title1 = prefixF + "_MIST-Params.txt";
  	title2 = "["+title1+"]";
	paramPath = outDir + fS + title1; /* restore file separator for imageJ saves */
	if (File.exists(paramPath)) deletedFile = File.delete(paramPath);
	run("Text Window...", "name=tempParams");
	saveAs("Text", paramPath);
	run("Close");
	File.append(paramsTxt, paramPath);
	/* start direct run section */
	/* NOTE: you can't just simply edit the params file as the variable names are different cases */
	commandString = "gridwidth=" + gridWidth + " gridheight=" +  gridHeight + " starttilerow=" +  startTileRow + " starttilecol=" + startTileCol + " imagedir=[" + inDir + "] filenamepattern=" + fPattern + " filenamepatterntype=ROWCOL gridorigin=UL assemblefrommetadata=false assemblenooverlap=false globalpositionsfile=[] numberingpattern=HORIZONTALCOMBING startrow=" + startRow + " startcol=" + startCol + " extentwidth=" + extentWidth + " extentheight=" + extentHeight + " timeslices=0 istimeslicesenabled=false outputpath=[" + outDir + "] displaystitching=" + checkToText(displayStitching) + " outputFullImage=false outputmeta=" + checkToText(outputMeta) + " outputimgpyramid=" + checkToText(outputImgPyramid) + " blendingmode=" + blendingMode + " blendingalpha=" + d2s(blendingAlpha, 1) + " compressionmode=LZW outfileprefix=" + outFilePrefix + " unit=" + mistUnit + " unitx=" + pixelW + " unity=" + pixelH + " programtype=AUTO " + numCPUsStr + " loadfftwplan=true savefftwplan=true fftwplantype=" + fftwPlanType + " fftwlibraryname=libfftw3 fftwlibraryfilename=libfftw3.dll planpath=[" + fftwPlanDir + "] fftwlibrarypath=[" + fftwDir + "] stagerepeatability=" + d2s(stageRepeatability, 0) + " horizontaloverlap=" + d2s(horizontalOverlap, 1) + " verticaloverlap=" + d2s(verticalOverlap, 1) + " numfftpeaks=" + d2s(numFFTPeaks, 0) + " overlapuncertainty=" + d2s(overlapUncertainty, 1) + " isusedoubleprecision=" + checkToText(useDoublePrecision) + " isusebioformats=false issuppressmodelwarningdialog=false isenablecudaexceptions=false translationrefinementmethod=" + transRefinement + " numtranslationrefinementstartpoints=" + d2s(transRefinementsPts, 0) + " headless=true loglevel=HELPFUL debuglevel=HELPFUL";
	if (headlessMode){
		IJ.log("MIST stitch options\n" + commandString);
		showStatus("!MIST-stitching, please wait", "flash cyan");
		startStitchTime = getTime();
		run("MIST", commandString);
		endStitchTime = getTime();
		stitchingTime = endStitchTime - startStitchTime;
		maxWaitOpen = maxOf(10, gridWidth * gridHeight * imageWidth * imageHeight /1000);
		startOpen = getTime();
		waitForOpenWindow("temp.ome.tif", 100, 500, maxWaitOpen); /* windowName, testWait, minWait, maxWait */
		openTime = getTime();
		openingTime = openTime - startOpen;
		IJ.log("Stitching and blending took " + stitchingTime + " mS, opening took " + openingTime + " mS out of maxWaitOpen of " + maxWaitOpen + " mS");
		if (isOpen("temp.ome.tif")){
			selectImage("temp.ome.tif");
			if (is("composite")) run("Stack to RGB");
			dC = getDateCode();
			descriptiveName = "Stitched_" + toLowerCase(blendingMode + "_" + numFFTPeaks + "fftPks_" + fftwPlanType + "_" + transRefinement + "_" + dC + ".tif");
			descriptiveName = replace(descriptiveName, "_hill_climb", "-hc"); 
			outputTitle = replace(title1, "Params.txt", descriptiveName);
			if (autosaveRGB_Tiff){
				saveAs("Tiff", outDir + fS + outputTitle);
				IJ.log("Stitched image saved as " + outputTitle);
				closeImageByTitle("temp.ome.tif");
				IJ.log("Original multichannel stitch 'temp.ome.tif' closed; let me know if you don't like this behavior");
			}
		}
	}
	else {
		String.resetBuffer;
		String.copy(paramPath);
		IJ.log("Now run MIST loading new parameter file:\n" + paramPath + "\nThis path has been copied to the system clipboard\nTest with sub-grid");
		waitForUser("MIST parameter file saved and path copied to the system clipboard: Paste into MIST 'Load Params' requester");
		/* Would like to kill any old imageJ/Fiji MIST windows at this point but I have not figured out a TASKILL command that worked for the MIST window. */
		run("MIST");
		showStatus("Paste clipboard into MIST 'Load Params'", "flash green");
	}
	if (File.exists(paramPath)){
		call("ij.Prefs.set", prefsNameKey+"paramPath", paramPath);
		globalPositionPath = replace(paramPath, "Params.txt", "global-positions-0.txt");
		if (File.exists(globalPositionPath)) call("ij.Prefs.set", "asc.stitch.helpers.lastPositionFile", globalPositionPath);
		else IJ.log("Global position file not found so not set in preferences for next use");
	}
	else IJ.log("Current parameter file not found, so not set in preferences for next use");
	if (closeOriginal) closeImageByTitle(fileName);
	setBatchMode("exit & display");
	beep();wait(400);beep();wait(800);beep();
	call("java.lang.System.gc");
	run("Collect Garbage"); 
	showStatus("Completed macro: " + macroL, "flash green");
	/* End of Stitch_DSX_Mosaic_Using_Selected_Image_and_All_Others_in_Same_Directory macro */
	/*
		( 8(|)	( 8(|)	Required Functions	@@@@@:-)	@@@@@:-)
		
	*/
	function checkToText(trueFalse){
		if(trueFalse==true) trueString = "true";
		else if(trueFalse==false) trueString = "false";
		else trueString = "checkToText function error - expecting true or false input only";
		return trueString;
	}
	function closeImageByTitle(windowTitle) {  /* Cannot be used with tables */
		/* v181002: reselects original image at end if open
		   v200925: uses "while" instead of if so it can also remove duplicates
		   v230411:	checks to see if any images open first.
		*/
		if(nImages>0){
			oIID = getImageID();
			while (isOpen(windowTitle)) {
				selectWindow(windowTitle);
				close();
			}
			if (isOpen(oIID)) selectImage(oIID);
		}
	}
	function countArrayElementsWithString(thisArray, stringIn){
		for(i=0, c=0;i<thisArray.length;i++) if(indexOf(thisArray[i], stringIn)>=0) c++;
		return c;
	}
	function getDateCode(){
		/* v170823 */
		getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
		month = month + 1; /* Month starts at zero, presumably to be used in array */
		if(month<10) monthStr = "0" + month;
		else monthStr = ""  + month;
		if (dayOfMonth<10) dayOfMonth = "0" + dayOfMonth;
		dateCodeUS = monthStr+dayOfMonth+substring(year, 2);
		return dateCodeUS;
	}
	function getDSXExifTagFromMetaData(metaData, tagName, lastInstance) {
	/* metaData is string generated by metaData = getMetadata("Info");	
		v230120: 1st version  version b
		v230526: This version has "lastInstance" option
	*/
		tagBegin = "<"+tagName+">";
		if (!lastInstance) i0 = indexOf(metaData, tagBegin);
		else  i0 = lastIndexOf(metaData, tagBegin);
		if (i0!=-1) {
			tagEnd = "</" + tagName + ">";
			i1 = indexOf(metaData, tagEnd, i0);
			tagLine = substring(metaData, i0, i1);
			tagValue = substring(tagLine, indexOf(tagLine, ">")+1, tagLine.length);
		}
		else tagValue = "" + tagName + " not found in metaData";
		return tagValue;
	}
	function getDSXPanoFilesWithSameExtension(dir, ext) {
		dsxMapFiles = newArray();
		list = getFileList(dir);
		for (i=0; i<lengthOf(list); i++) {
			listName = list[i]; 
			if (endsWith(listName, "/"))
				getDSXPanoFilesWithSameExtension(""+dir+listName, ext);
			if(endsWith(listName, "." + ext) && indexOf(listName, "_X")>0 && indexOf(listName, "_Y")>0){
				iExt = lastIndexOf(listName, "." + ext);
				if(substring(listName, iExt-10, iExt-8)=="_X" && substring(listName, iExt-5, iExt-3)=="_Y") dsxMapFiles = Array.concat(dsxMapFiles, listName);
			}
		}
		return dsxMapFiles;
	}
	function getExifData(exifSource){
		/* uses exifReader plugin: https://imagej.net/plugins/exif-reader.html
		The exif reader plugin will not load a new image directly if one is open, it will only use the open image
		- this is why this version opens a new image separately
		v230511: 1st versions
		v230512: More careful about closing.
		v230522-6: Attempt to better handle already open source images
		*/
		exifImageTitle = File.getName(exifSource);
		if (isOpen(exifImageTitle)){
			exifImageWasOpen = true;
			selectWindow(exifImageTitle);
		}
		else {
			open(exifSource);
			exifImageWasOpen = false;
		}
		exifImageID = getImageID();
		exifPrefix = "EXIF Metadata for ";
		exifTitle = exifPrefix + getTitle();
		run("Exif Data...");
		wait(10);
		selectWindow(exifTitle);
		metaInfo = getInfo("window.contents");
		if (!exifImageWasOpen){
			selectImage(exifImageID);
			close();
		}
		close(exifTitle);
		return metaInfo;
	}
	function getUniqueElementPrefixes(thisArray, suffixStart){
	/* used to find different map/mosaic sets within a given file list
		v230315: 1st version that actually works
		*/
		prefixes = newArray(substring(thisArray[0], 0, lastIndexOf(thisArray[0], suffixStart)));
		for(i=1;i<thisArray.length;i++){
			prefix = substring(thisArray[i], 0, lastIndexOf(thisArray[i], suffixStart));
			for(j=0, newPrefix=true;j<prefixes.length;j++) if (prefixes[j]==prefix) newPrefix=false;
			if (newPrefix) prefixes = Array.concat(prefixes, prefix);
		}
		return prefixes;	
	}
	function sensibleUnits(pixelW, inUnit){
		/* v220805: 1st version
			v230808: Converts inches to mm automatically.
			v230809: Removed exit, just logs without change.
			v240209: Does not require indexOfArray function.
		*/
		kUnits = newArray("m", "mm", getInfo("micrometer.abbreviation"), "nm", "pm");
		if (inUnit=="inches"){
			inUnit = "mm";
			pixelW *= 25.4;
			IJ.log("Inches converted to mm units");
		}
		if(startsWith(inUnit, "micro") || endsWith(inUnit, "ons") || inUnit=="um" || inUnit=="µm") inUnit = kUnits[2];
		for (i=0, iInUnit=-1; i<kUnits.length; i++)
			if (inUnit==kUnits[i]) iInUnit = i;
		if (iInUnit<0)
			IJ.log("Scale unit \(" + inUnit + "\) not in unitChoices for sensible scale function, so units not optimized");
		else {
			while (round(pixelW)>50) {
				pixelW /= 1000;
				iInUnit -= 1;
				inUnit = kUnits[iInUnit];
			}
			while (pixelW<0.02){
				pixelW *= 1000;
				iInUnit += 1;
				inUnit = kUnits[iInUnit];				
			}
		}
		outArray = Array.concat(pixelW, inUnit);
		return outArray;
	}
	function toSentenceCase(stringIn){
		/* v230215 1st version */
		return toUpperCase(substring(stringIn, 0, 1)) + toLowerCase(substring(stringIn, 1));
	}
	function waitForOpenWindow(windowName, testWait, minWait, maxWait) {
		/* v230511: 1st version
			v240222: Flash green on completion.
			v240227: Flash pink for each test.
			v240311: Adds option to keep waiting if window has not opened
		*/
		wait(minWait);
		maxIterations = maxWait/testWait;
		for (i=0; i<maxIterations; i++){
			showProgress(i, maxIterations);
			showStatus("Waiting for " + windowName, "flash pink");
			if (!isOpen(windowName)) wait(testWait);
			else i = maxIterations;
		}
		if (!isOpen(windowName)){
			keepWaiting = getBoolean("Target window is not open; do you want to continue waiting?");
			if (keepWaiting && !isOpen(windowName)) waitForOpenWindow(windowName, testWait, minWait, maxWait);
			else (!isOpen(windowName)) exit("Gave up waiting for " + windowName);
		}
		showStatus("The wait for " + windowName + " is over", "flash green");
	}