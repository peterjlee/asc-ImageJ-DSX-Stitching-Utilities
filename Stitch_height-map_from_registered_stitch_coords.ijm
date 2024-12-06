/* This macro creates a height-map image from a list of registered DSX images
	PJL NHMFL
	v230510: 1st working version.
	v230511: Created waitForOpenWindow function. Added stitching options.
	v230515: Added ability to use MIST-Global-positions file.
	v230522: Removes an unnecessary image duplication.
	v230526: Updated DSX EXIF functions and altered batchmode operation to allow viewing of images before saving. f1: Replaced getDir with getDirectory for ImageJ 1.54g10
	v230808: Allows configuration files without full path (i.e. newer Grid/Collection Stitching plugin). F1-2: updated safeSaveAndClose.
	v231031: Added blended area fraction option.
	v240221: Now output height calibration to file instead of just to the diagnostics log. b: Options added for calibration files. c-d: Improved summary file. e: Can skip reading all calibrations. f: You can just output the height calibration for the 16-bit images.
	v240222: Major revision: 32-bit stitch now calculated from 16-bit stitch and no intermediate 32-images are created (use the dedicated "Convert_Active_DSX_Image_And_All_Others_in_Same_Directory_and_Extract_HMaps" macro for that). The height calibration is added to the 16-bit stitch name.
	v240222a: Restored Linear Blending. b: Updated "Wait for" function.
	v240223: Wording tweaks.
	v240225: fusionVal not behaving as numeric value.
	v240226: Improved filenames (added uncleanLabel function).
	v240227: Default position file is last-saved position file (if available). F1: Update safeSaveAndClose.
*/
	macroL = "Stitch_height-map_from_Registered_Stitch_Coords_v240226-f1.ijm";
	iMMagickPath = findAppPath("ImageMagick", "magick.exe", "not found");
	if (iMMagickPath=="not found") exit("ImageMagick is required for this macro and it could not be found");
	fS = File.separator;
	um = getInfo("micrometer.abbreviation");
	prefsNameKey = "stitch.hm.registered.";
	lastPositionFile = call("ij.Prefs.get", "asc.stitch.helpers.lastPositionFile", "");
	if (lastPositionFile=="" || !File.isFile(lastPositionFile)) lastPositionFile = File.getDefaultDir;
	/* ASC Dialog style */
	infoColor = "#006db0"; /* Honolulu blue */
	instructionColor = "#798541"; /* green_dark_modern (121, 133, 65) AKA Wasabi */
	infoWarningColor = "#ff69b4"; /* pink_modern AKA hot pink */
	infoFontSize = 12;
	Dialog.create("Import options: " + macroL);
		Dialog.addMessage("This macro expects a stitch registration file created by IJ stitch or MIST global positions file\nIt also expects the referenced files to be DSX images that include a height map as the 2nd frame.\nFor MIST global-positions files the dsx images need to be in the same directory", infoFontSize, infoColor);
		Dialog.addFile("File of stitched image positions", lastPositionFile);
		Dialog.setInsets(-5, 200, 20);
		Dialog.addMessage("Use 'registered' file created by IJ stitch or MIST 'global positions' file", infoFontSize, instructionColor);
		Dialog.addString("Height maps saved to new sub-dir", "hm", 10);
		Dialog.addString("Suffix to add to height map TIF", "_hm", 10);
		outputOptions = newArray("1: Extract height calibration file only", "2: Stitch_16-bit height map only", "3: 16-bit & calculated_32-bit map with intensity = height in " + um);
		Dialog.addRadioButtonGroup("Output options \(Options 2-3 will also create a directory of 16-bit height maps\)", outputOptions, 2, 2, outputOptions[2]);
		if (isOpen("Stitched Image")) Dialog.addCheckbox("Close currently open stitched images", true);
		blendingOptions = newArray("Linear  ", "Average  ", "Median  ", "Max. Intensity  ", "Min. Intensity  ", "None"); /*Note: These values should be the exact names used in the stitching configuration string but I have modified them here for spacing. They are corrected later. */
		Dialog.setInsets(10, 20, -5);
		Dialog.addRadioButtonGroup("Blending:", blendingOptions, 1, blendingOptions.length, blendingOptions[0]);
		blendingTxt = "Linear Blending: \tIn the overlapping area, the intensities are smoothly adjusted between overlapping images.\n";
		blendingTxt += "Average: \tIn the overlapping area, the average intensity of all overlapping images is used.\n";
		blendingTxt += "Median: \tIn the overlapping area, the median intensity of all overlapping images is used.\n";
		blendingTxt += "Max. Intensity: In the overlapping area, the maximum intensity between all overlapping images is used.\n";
		blendingTxt += "Min. Intensity: In the overlapping area the minimum intensity between all overlapping images is used.\n";
		Dialog.setInsets(0, 20, 0);
		Dialog.addMessage(blendingTxt, infoFontSize-1, infoColor);
		Dialog.addNumber("Fusion alpha \(>1 is non linear\):", 1.5, 1, 4, "default: 1.5");
		Dialog.addRadioButtonGroup("Blended Area Fraction, TBH this doesn't seem to have much impact \(default is 0.2\):", Array.resample(Array.getSequence(2), 11), 1, 5, "0.2");
		miscOptions = newArray("Subtract minimum height value \(-1%\) from  final maps?", "32-bit map: Stretch viewing contrast range to height range?", "Extract height calibration from 1st file only", "Close new stitched height maps after saving", "Diagnostic output");
		miscChecks = newArray(true, true, true, false, false);
		Dialog.setInsets(10, 20, 0);
		Dialog.addCheckboxGroup(3, 2, miscOptions, miscChecks);
		Dialog.addMessage("16-bit maps: The intensity level to " + um + " conversion factor is saved in a file ending '_heightCal.txt'", infoFontSize, infoColor);
	Dialog.show();
		regFilePath = Dialog.getString();
		hSubName = Dialog.getString();
		hSuffix = Dialog.getString();
		outputOption = Dialog.getRadioButton();
		if (!startsWith(outputOption, "1")) makeHM16 = true;
		else makeHM16 = false;
		if (startsWith(outputOption, "3")) calcHM32 = true;
		else calcHM32 = false;
		if (isOpen("Stitched Image")){
			if (Dialog.getCheckbox()) close("*Stitched Image*");
		}
		blendingOption = replace(Dialog.getRadioButton(), "  ", "");
		blendingOption = replace(blendingOption, "Linear", "Linear Blending");
		fusionVal = Dialog.getNumber();
		fusionFraction = Dialog.getRadioButton();
		bshScript = "mpicbg.stitching.fusion.BlendingPixelFusion.fractionBlended = " + fusionFraction;
		IJ.log("Temporary fractionBlend applied:")
		eval("bsh", bshScript);
		subtractBase = Dialog.getCheckbox();
		stretchView32 = Dialog.getCheckbox();
		extractFirstOnly = Dialog.getCheckbox();
		closeHM = Dialog.getCheckbox();
		diagnostics = Dialog.getCheckbox();
	if (File.isDirectory(regFilePath)) regFilePath = File.openDialog("A directory was chosen, please find a registration file");
	if (!File.exists(regFilePath)) exit("Registration file not found");
	registeredString = File.openAsString(regFilePath);
	firstIJSHeaderLine = "# Define the number of dimensions we are working on";
	firstMISTGlobalHeaderLine = "file: ";
	lastIJSHeaderLine = "# Define the image coordinates\n";
	if (indexOf(registeredString, firstIJSHeaderLine)==0) regType = "ijSReg";
	else if (indexOf(registeredString, firstMISTGlobalHeaderLine)==0) regType = "mistGlobal";
	else exit("Registration file does does not have the expected first line of a registered IJS or Global MIST file");
	headerText = firstIJSHeaderLine + "\ndim = 2\n\n" + lastIJSHeaderLine;
	if (regType=="ijSReg"){
		iLastIJSHeaderLine = indexOf(registeredString, lastIJSHeaderLine)+lastIJSHeaderLine.length;
		if (iLastIJSHeaderLine<0) exit("Expected header line not found: " + lastIJSHeaderLine);
		fileLineList = substring(registeredString, iLastIJSHeaderLine);
		iFile = 0;
		if (indexOf(registeredString, fS)>0) prePath = "";
		else prePath = File.getParent(regFilePath) + fS;
	}
	else {
		fileLineList = registeredString;
		iFile = 6;
		prePath = File.getParent(regFilePath) + fS;
		posString = "position: ";
	} 
	fileLines = split(fileLineList, "\n");
	if (diagnostics) IJ.log("File lines in reg file: " + fileLines.length);
	listOfFiles = newArray();
	listOfHtFiles = newArray();
	htDepthCals = newArray();
	suffixTextLines = newArray();
	setBatchMode(true);
	heightCalSummaryHeader = "Summary of height calibrations \(I = Intensity level\)\npm per I," + um + " per I,Original depth range \(" + um + "\),Filename";
	heightCalSummary = heightCalSummaryHeader;
	for (i=0, j=0; i<fileLines.length; i++){
		listOfFiles[i] = prePath + substring(fileLines[i], iFile, indexOf(fileLines[i], ";"));
	}
	for (i=0, j=0; i<fileLines.length; i++){
		showProgress(i, fileLines.length);
		showStatus("Extracting original file information and 16-bit height maps");
		if (diagnostics) IJ.log("File " + i+1 + ": " + listOfFiles[i]);
		if (diagnostics){
			IJ.log("File list:");
			Array.print(listOfFiles);
		}
		if (File.exists(listOfFiles[i])){
			suffixTextLines[j] = substring(fileLines[i], indexOf(fileLines[i], ";"));
			if (regType=="mistGlobal") suffixTextLines[j] = "; ; " + substring(suffixTextLines[j], lastIndexOf(suffixTextLines[j], "position: ")+10, indexOf(suffixTextLines[j], "\)")+1); /* Convert to IJ Stitch format for reassembling */
			currentFilenameWoE = File.getNameWithoutExtension(listOfFiles[i]);
			if (j==0){
				metaData = getExifData(listOfFiles[i]);
				if (diagnostics) IJ.log("metaData from: " + listOfFiles[i] + "\n" + metaData);
				mapPrefix = substring(currentFilenameWoE, 0, lastIndexOf(currentFilenameWoE, "X")-1);
				folderPath = File.getParent(listOfFiles[i]);
				if (!endsWith(folderPath, fS)) folderPath += fS;
				hFolderPath = folderPath + hSubName;
				if (diagnostics) IJ.log("Create new sub-directory for height maps: " + hFolderPath);
				if (!File.exists(hFolderPath)){
					File.makeDirectory(hFolderPath);
					if (!File.exists(hFolderPath)) exit("Unable to create output directory:\n" + hFolderPath);
				}
				/* get scales from 1st file - if the scales aren't the same for all files the montaging will not work anyway.
				Note: header calibrations are in pm so parseInt is more efficient that parseFloat and does no effect real accuracy */
				umPerPixelX = parseInt(getDSXExifTagFromMetaData(metaData, "ColorDataPerPixelX", true)) * 10E-7;
				umPerPixelY = parseInt(getDSXExifTagFromMetaData(metaData, "ColorDataPerPixelY", true)) * 10E-7;
				umPerPixelOrX = parseInt(getDSXExifTagFromMetaData(metaData, "ImageDataPerPixelX", true)) * 10E-7;
				umPerPixelOrY = parseInt(getDSXExifTagFromMetaData(metaData, "ImageDataPerPixelY", true)) * 10E-7;
				if (umPerPixelX!=umPerPixelOrX) IJ.log("Note that for " + listOfFiles[i] + " the stored output X scale \(" + umPerPixelX + " microns per pixel\) was different from the original acquisition scale \(" + umPerPixelOrX + " microns per pixel\). The output scale is used.");
				aspectRatio = umPerPixelX/umPerPixelY;
			}
			else if (!extractFirstOnly) metaData = getExifData(listOfFiles[i]);
			heightPath = listOfFiles[i] + "[2]";
			newHtPath = hFolderPath + fS + File.getNameWithoutExtension(listOfFiles[i]) + hSuffix + ".tif";
			if (makeHM16){
				imHtExec = "\"" + iMMagickPath + "\" " + "\"" + heightPath + "\"  \"" + newHtPath + "\"";
				if (diagnostics) IJ.log("IM tiff height map save execString:\n" + imHtExec);
				exec(imHtExec);
			}
			listOfHtFiles[j] = newHtPath;
			depthCalStr = getDSXExifTagFromMetaData(metaData, "ColorDataPerPixelZ", true);
			if (diagnostics) IJ.log("depth cal from header: " + depthCalStr);
			depthCal = parseInt(depthCalStr);
			if (depthCal<1) depthCal = parseInt(getDSXExifTagFromMetaData(metaData, "HeightDataPerPixelZ", true));
			depthCalOr = parseInt(getDSXExifTagFromMetaData(metaData, "ImageDataPerPixelZ", true));
			if (depthCal>1 || depthCalOr>1){
				heightString = newHtPath + ":\n";
				if (depthCal>1){
					depthCalSt = d2s(depthCal, 7);
					depthCalMicrons = depthCal * 10E-7;
					preStr = ": Montage ";
				}
				else if (depthCalOr>1){
					depthCalSt = d2s(depthCalOr, 7);
					depthCalMicrons = depthCalOr * 10E-7;
					preStr = ": Original ";
				}
				fullDepthRangeMicrons = d2s(256 * 256 * depthCalMicrons, 5); /* depth map is 16-bit */
				if (extractFirstOnly && j==0){
					heightString += "" + depthCalSt + preStr + "Height Map calibration \(pm\/intensity Level\)\n";
					heightString += "" + d2s(depthCalMicrons, 7) + preStr + "Height Map calibration \(" + um + "\/intensity Level\)\n";
					heightString += "" + d2s(fullDepthRangeMicrons, 7) + preStr + "Full 16-bit Height Map Range \(" + um + "\)\n";
					while (endsWith(heightString, "\n"))
						heightString = substring(heightString, 0, lastIndexOf(heightString, "\n"));
					if (diagnostics) IJ.log(heightString);
					heightCalExportPath = replace(newHtPath, ".tif", "_heightCal.txt");
					File.saveString(heightString, heightCalExportPath);
					IJ.log("Intensity to height calibration file saved to " + heightCalExportPath);
					if (!makeHM16) exit("Intensity to height calibration file saved to " + heightCalExportPath);
				}
				else heightCalSummary += "\n" + depthCalSt + "," + depthCalMicrons + "," + fullDepthRangeMicrons + "," + newHtPath;
				htDepthCals[j] = depthCalMicrons;
			}
			else IJ.log(listOfFiles[i] + ": No height map information found");
			j++;
		}
	}
	if (!extractFirstOnly) tileN = j;
	else {
		for (i=0, tileN=0; i<listOfFiles.length; i++)
			tileN = tileN + File.exists(listOfFiles[i]);
	}
	if (tileN<1) exit("No map files files found at their original locations: check to see if they moved");
	else if ((!extractFirstOnly && htDepthCals.length<tileN) || htDepthCals.length<1) exit(htDepthCals.length + " height maps found out of " + tileN + " tiles");
	if (!extractFirstOnly && heightCalSummary!=heightCalSummaryHeader){
		heightCalSummaryPath = replace(newHtPath, ".tif", "-etc_heightCalSummary.csv");
		File.saveString(heightCalSummary, heightCalSummaryPath);
		IJ.log("Summary of intensity:height calibrations saved to " + heightCalSummaryPath);
	}
	microscopeSettings = "Depth calibrations in microns:\n";
	if (!extractFirstOnly){
		for (i=0; i<htDepthCals.length; i++) microscopeSettings += listOfHtFiles[i] + ": " + htDepthCals[i] + "\n";
	}
	else microscopeSettings += listOfHtFiles[0] + ": " + htDepthCals[0] + "\n";
	microscopeSettings += "\nDSX ref codes:\n";
	refCodes = newArray("OverlapSize", "StitchingRowCount", "StitchingColumnCount", "ExtendMode", "ZRangeMode", "ZSliceTotal", "ZSliceCount", "ZStartPosition", "ZEndPosition", "ZRange", "ZPitchTravel", "StagePositionX", "StagePositionY", "ObjectiveLensID", "ObjectiveLensType", "ObjectiveLensMagnification", "ZoomMagnification", "OpiticalZoomMagnification", "DigitalZoomMagnification", "MapRoiTop", "MapRoiLeft", "MapRoiWidth", "MapRoiHeight", "ImageAspectRatio", "ImageTrimmingSize");
	for (i=0; i<refCodes.length; i++) microscopeSettings += refCodes[i] + ": " + getDSXExifTagFromMetaData(metaData, refCodes[i], true) + "\n";
	if (diagnostics) IJ.log(microscopeSettings);
	File.saveString(microscopeSettings, folderPath + mapPrefix + "_microscopeSettings.txt");
	ht16String = "" + headerText;
	h16IntMin = 65536;
	h16IntMax = 0;
	hCalMin = 65536 * htDepthCals[0];
	hCalMax = 0;
	if (extractFirstOnly) dCal = htDepthCals[0];
	for(i=0; i<listOfHtFiles.length; i++){
		showProgress(i, listOfHtFiles.length);
		showStatus("Add ImageJ/Fiji scales to hm16 files");
		if (!File.exists(listOfHtFiles[i])) IJ.log(listOfHtFiles[i] + " not successfully saved");
		else {
			open(listOfHtFiles[i]);
			hmID = getImageID();
			getStatistics(null, null, h16Min, h16Max);
			h16IntMin = minOf(h16IntMin, h16Min);
			h16IntMax = maxOf(h16IntMax, h16Max);
			if (!extractFirstOnly) dCal = htDepthCals[i];
			hCalMin = minOf(hCalMin, h16Min * dCal);
			hCalMax = maxOf(hCalMax, h16Max * dCal);
			run("Set Scale...", "distance=1 known="+umPerPixelX+" pixel="+aspectRatio+" unit=um");
			saveAs(listOfHtFiles[i]);
			close();
			ht16String += "" + listOfHtFiles[i] + suffixTextLines[i] + "\n";
		}
	}
	h16IntRange = h16IntMax - h16IntMin;
	hCalRange = hCalMax - hCalMin;
	layoutPath16 = folderPath + mapPrefix + "_tiles_hm16.txt";
	File.saveString(ht16String, layoutPath16);
	stitchedTitle = "" + mapPrefix + "_hm_IJ-Stitched";
	if (regType=="mistGlobal") stitchedTitle += "_MIST-Reg";
	if (diagnostics) IJ.log("saving HM16 layout to:\n" + layoutPath16);
	if (makeHM16){
		if (File.exists(layoutPath16)){
			showStatus("!Stitching 16-bit height map", "flash #4C41849 2000ms");
			/* Uses "old" version for IJ stitch - seems to produce better results */
			run("Stitch Collection of Images", "layout=["+layoutPath16+"] channels_for_registration=[Red, Green and Blue] rgb_order=rgb fusion_method=[&blendingOption] fusion="+fusionVal+" regression=0.30 max/avg=3.50 absolute=3.50");
			waitForOpenWindow("Stitched Image", 500, 1000, 1000 * listOfHtFiles.length);
			run("Set Scale...", "distance=1 known="+umPerPixelX+" pixel="+aspectRatio+" unit=um");
			if (subtractBase){
				baseH16 = h16IntMin - 0.01 * h16IntRange; /* buffer of 1 to separate from zero */
				run("Subtract...", "value=" + baseH16);
				run("Min...", "value=0");
				stitchedTitle += "_subMin";
			}
			if (!extractFirstOnly) dCal = htDepthCals[i];
			else dCal = htDepthCals[0];
			calSt = "_" + d2s(dCal, 7) + "umpI";
			stitchedTitle16 = unCleanLabel(replace(stitchedTitle, "_hm_", "_hm16_") + calSt + ".tif");
		}
		else IJ.log(layoutPath16 + " not found");
	}
	if (!calcHM32) safeSaveAndClose("tiff", folderPath, stitchedTitle16, closeHM);
	else {
		safeSaveAndClose("tiff", folderPath, stitchedTitle16, false);
		stitchedTitle32 = replace(stitchedTitle, "_hm_", "_hm32_");
		run("32-bit");
		run("Multiply...", "value=" + dCal);
		rename(stitchedTitle32);
		if (stretchView32){
			run("Enhance Contrast...", "saturated=0");
			stitchedTitle32 += "_sView";
		} 
		stitchedTitle32 += ".tif";
		stitchedTitle32 = unCleanLabel(stitchedTitle32);
		safeSaveAndClose("tiff", folderPath, stitchedTitle32, closeHM);
	}
	if (is("Batch Mode")) setBatchMode("exit & display");
	beep();wait(400);beep();wait(800);beep();
	call("java.lang.System.gc");
	run("Collect Garbage"); 
	showStatus("Completed macro: " + macroL, "flash green");
	/* End of Stitch_height-map_from_Registered_Stitch_Coords */
	
	/*
		( 8(|)	( 8(|)	All ASC Functions	@@@@@:-)	@@@@@:-)
	*/
	function findAppPath(appName, appEx, defaultPath) {
		/* v210921 1st version: appName is assumed to be the app folder name, appEx is the executable, default is the default return value
			v211018: assumes specific executable path stored in prefs Prints message rather than exits when app not found
			v211213: fixed defaultPath error
			v211214: Adds additional location as packaged within a Fiji/IJ distribution
			v220121: Changed fS line
			v230803: Replaced getDir with getDirectory for ImageJ 1.54g10 
		*/
		functionL = "findAppPath_v230803";
		fS = File.separator;
		ijPath = getDirectory("imagej");
		appsPath = substring(ijPath, 0, lengthOf(ijPath)-1);
		appsPath = substring(appsPath, 0, lastIndexOf(appsPath, fS));
		appFound = false;
		prefsName = "asc.external.paths." + toLowerCase(appName) + "." + appEx;
		appPath = call("ij.Prefs.get", prefsName, defaultPath);
		appLoc = ""+fS+appName+fS+appEx;
		cProg = "C:"+fS+"Program Files";		
		defAppPaths = newArray(cProg+fS+"Utilities"+appLoc, cProg+" \(x86\)"+fS+"Utilities"+appLoc, cProg+appLoc, cProg+" \(x86\)"+appLoc, appsPath+appLoc, ijPath+"Apps"+appLoc);
		if (!File.exists(appPath)) { 
			for(i=0;i<lengthOf(defAppPaths);i++){
				if (File.exists(defAppPaths[i])){
					appPath = defAppPaths[i];
					call("ij.Prefs.set", prefsName, appPath);
					appFound = true;
					i = lengthOf(defAppPaths);
				}
			}
		}
		else appFound = true;
		if (appFound==false){
			Dialog.create("Find location of " + appEx + " version: " + functionL);
			Dialog.addMessage(appEx + " can provide additional functionality to this macro\nbut has not been found in the expected locations");
			Dialog.addCheckbox("Get me out of here, I don't want to try and find " + appName + ", whatever that is", false);
			Dialog.addFile("Locate " + appEx + ":", "C:"+fS+"Program Files");
			Dialog.addMessage("If found, the location will be saved in prefs for future use:\n" + prefsName);
			Dialog.show;
			if (Dialog.getCheckbox) appFound = false;
			else {
				appPath = Dialog.getString();
				if (!File.exists(appPath)) print(appEx + " not found");
				else {
					call("ij.Prefs.set", prefsName, appPath);
					appFound = true;
				}
			}
		}
		if (appFound) return appPath;
		else return defaultPath;
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
	function safeSaveAndClose(filetype, path, fileSaveName, closeImageIfSaved){
		/* v230411: 1st version reworked
			v230812: Uses full dialog which should save time for non-saves, includes options to change the directory and filetype.
			v230814: Close by imageID not filename. Added option to override closeImageIfSaved.
			v230915: Saves if there is no change in path rather than getting stuck in loop.
			v230920: Allows empty path string.
			v240315: Fixed RadioButton issue.
		*/
		functionL = "safeSaveAndClose_v240315";
		imageID = getImageID();
		fS = File.separator;
		filetypes = newArray("tiff", "png", "jpeg");
		extensions = newArray("tif", "png", "jpg");
		for (i=0; i<3; i++){
			if (filetype==filetypes[i]) extension = extensions[i];
			else extension = extensions[0];
		}
		if (!endsWith(fileSaveName, extension)){
			if (lastIndexOf(fileSaveName, ".")>fileSaveName.length-5) fileSaveName = substring(fileSaveName, 0, lastIndexOf(fileSaveName, ".")+1) + extension;
			else fileSaveName += "." + extension;
		}
		if (path!=""){
			if(endsWith(path, fS)) path = substring(path, 0, path.length-1);
			fullPath = path + fS + fileSaveName;
		}
		else fullPath = "";
		newSave = false;
		if (!File.exists(fullPath) && fullPath!=""){
			saveAs(filetype, fullPath);
			if (File.exists(fullPath)) newSave = true;
		}
		if (!newSave){
			Dialog.create("Options: " + functionL);
				if (path!=""){
					Dialog.addMessage("File: " + fileSaveName + " already exists in\n" + path);
					Dialog.addMessage("If no changes are made below, the existing file will be overwritten");
				}
				Dialog.addString("Change the filename?", fileSaveName, fileSaveName.length+5);
				if (path=="") path = File.directory;
				Dialog.addDirectory("Change the directory?", path);
				// Dialog.addChoice("Change the filetype?", filetypes, filetypes[0]);
				Dialog.addRadioButtonGroup("Change the filetype?", filetypes, 1, filetypes.length, filetypes[0]);
				Dialog.addCheckbox("Don't save file", false);
				Dialog.addCheckbox("Close image \(imageID: " + imageID + ") after successful save", closeImageIfSaved);
			Dialog.show;
				newFileSaveName = Dialog.getString();
				newPath = Dialog.getString();
				// newFiletype = Dialog.getChoice();
				newFiletype = Dialog.getRadioButton();
				dontSaveFile = Dialog.getCheckbox();
				closeImageIfSaved = Dialog.getCheckbox();
			if (!dontSaveFile){
				if (!File.isDirectory(newPath)) File.makeDirectory(newPath);
				if (!endsWith(newPath, fS)) newPath += fS;
				for (i=0; i<3; i++){
					if (newFiletype==filetypes[i]){
						newExtension = extensions[i];
						if (extension!=newExtension) newfileSaveName = replace(newFileSaveName, extension, newExtension);
					}
				}
				newFullPath = newPath + newFileSaveName;
				if (!File.exists(newFullPath) || newFullPath==fullPath) saveAs(newFiletype, newFullPath);
				else safeSaveAndClose(newFiletype, newPath, newFileSaveName, closeImageIfSaved);
				if (File.exists(newFullPath)) newSave = true;
			}
		}
		if (newSave && closeImageIfSaved && nImages>0){
			if (getImageID()==imageID) close();
			else IJ.log(functionL + ": Image ID change so fused image not closed");
		}
	}
	function unCleanLabel(string) {
	/* v161104 This function replaces special characters with standard characters for file system compatible filenames.
	+ 041117b to remove spaces as well.
	+ v220126 added getInfo("micrometer.abbreviation").
	+ v220128 add loops that allow removal of multiple duplication.
	+ v220131 fixed so that suffix cleanup works even if extensions are included.
	+ v220616 Minor index range fix that does not seem to have an impact if macro is working as planned. v220715 added 8-bit to unwanted dupes. v220812 minor changes to micron and Ångström handling
	+ v231005 Replaced superscript abbreviations that did not work.
	+ v240124 Replace _+_ with +.
	*/
		/* Remove bad characters */
		string = string.replace(fromCharCode(178), "sup2"); /* superscript 2 */
		string = string.replace(fromCharCode(179), "sup3"); /* superscript 3 UTF-16 (decimal) */
		string = string.replace(fromCharCode(0xFE63) + fromCharCode(185), "sup-1"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
		string = string.replace(fromCharCode(0xFE63) + fromCharCode(178), "sup-2"); /* Small hyphen substituted for superscript minus as 0x207B does not display in table */
		string = string.replace(fromCharCode(181) + "m", "um"); /* micron units */
		string = string.replace(getInfo("micrometer.abbreviation"), "um"); /* micron units */
		string = string.replace(fromCharCode(197), "Angstrom"); /* Ångström unit symbol */
		string = string.replace(fromCharCode(0x212B), "Angstrom"); /* the other Ångström unit symbol */
		string = string.replace(fromCharCode(0x2009) + fromCharCode(0x00B0), "deg"); /* replace thin spaces degrees combination */
		string = string.replace(fromCharCode(0x2009), "_"); /* Replace thin spaces  */
		string = string.replace("%", "pc"); /* % causes issues with html listing */
		string = string.replace(" ", "_"); /* Replace spaces - these can be a problem with image combination */
		/* Remove duplicate strings */
		unwantedDupes = newArray("8bit", "8-bit", "lzw");
		for (i=0; i<lengthOf(unwantedDupes); i++){
			iLast = lastIndexOf(string, unwantedDupes[i]);
			iFirst = indexOf(string, unwantedDupes[i]);
			if (iFirst!=iLast) {
				string = string.substring(0, iFirst) + string.substring(iFirst + lengthOf(unwantedDupes[i]));
				i = -1; /* check again */
			}
		}
		unwantedDbls = newArray("_-", "-_", "__", "--", "\\+\\+");
		for (i=0; i<lengthOf(unwantedDbls); i++){
			iFirst = indexOf(string, unwantedDbls[i]);
			if (iFirst>=0) {
				string = string.substring(0, iFirst) + string.substring(string, iFirst + lengthOf(unwantedDbls[i]) / 2);
				i = -1; /* check again */
			}
		}
		string = string.replace("_\\+", "\\+"); /* Clean up autofilenames */
		string = string.replace("\\+_", "\\+"); /* Clean up autofilenames */
		/* cleanup suffixes */
		unwantedSuffixes = newArray(" ", "_", "-", "\\+"); /* things you don't wasn't to end a filename with */
		extStart = lastIndexOf(string, ".");
		sL = lengthOf(string);
		if (sL-extStart<=4 && extStart>0) extIncl = true;
		else extIncl = false;
		if (extIncl){
			preString = substring(string, 0, extStart);
			extString = substring(string, extStart);
		}
		else {
			preString = string;
			extString = "";
		}
		for (i=0; i<lengthOf(unwantedSuffixes); i++){
			sL = lengthOf(preString);
			if (endsWith(preString, unwantedSuffixes[i])) {
				preString = substring(preString, 0, sL-lengthOf(unwantedSuffixes[i])); /* cleanup previous suffix */
				i=-1; /* check one more time */
			}
		}
		if (!endsWith(preString, "_lzw") && !endsWith(preString, "_lzw.")) preString = replace(preString, "_lzw", ""); /* Only want to keep this if it is at the end */
		string = preString + extString;
		/* End of suffix cleanup */
		return string;
	}
	function waitForOpenWindow(windowName, testWait, minWait, maxWait) {
		/* v230511: 1st version.
			v240222: Flash green on completion.
		*/
		wait(minWait);
		maxIterations = maxWait/testWait;
		for (i=0; i<maxIterations; i++){
			showProgress(i, maxIterations);
			showStatus("Waiting for " + windowName);
			if (!isOpen(windowName)) wait(testWait);
			else i = maxIterations;
		}
		showStatus("The wait for " + windowName + " is over", "flash green");
	}