/* A macro to convert all Olympus VSI images images in a folder of a selected image to the original image location
	Partially based on code by Alex Herbert and by Michael Schmid-3 /* http://imagej.1557.n6.nabble.com/Save-XY-coordinates-batch-filenames-td3697141.html
	and structured after "BatchProcessFolders" example https://imagej.net/macros/BatchProcessFolders.txt
	v210903: 1st version Updated functions: 5/16/2022 3:56 PM
	v220818: restoreExit removed
	v230111: Now imports scales correctly for auto-scaled montages exported from the DSX software.
	v230118-9: More information provided in dialog. v230119 just adds more information to dialog.
	v230120: Assumes that imageJ will import DSX metadata into info header. Exports height calibration as text files if available.
	v230510: Aspected pixels supported.
	v230516: Changed getDSXExifTag function name.
	v230522: MicronS corrected to um. Fully changed getDSXExifTag function name. v230522b: Can also create 32-bit maps. f1: 230803 replaced getDir.
	v231030: Fixed overview output directory errors. Now skips height map extraction ifThere is no embedded height map.
	v231031: Resaves height maps with lateral scales.
	v240221: Adds more information and formatting to the dialog.
	*/
	macroL = "Convert_Active_DSX_Image_And_All_Others_in_Same_Directory_to_TIFF_v240221.ijm";
	orImageID = getImageID();
	dir = getInfo("image.directory");
	fS = File.separator;
	count = 0;
	countFiles(dir);
	n = 0;
	um = getInfo("micrometer.abbreviation");
	depthCalP = -1;
	depthCalOrP = -1;
	iMMagickPath = findAppPath("ImageMagick", "magick.exe", "not found");
	fileTypes = newArray("tiff", "png", "jpeg", "pgm", "bmp", "gif ");
	if (iMMagickPath!="not found"){
		jpegQual = parseInt(call("ij.Prefs.get", "asc.lastsaved.jpeg.qual", 85));
		pngQual = parseInt(call("ij.Prefs.get", "asc.lastsaved.png.qual", 75)); /* ImageMagick PNG quality */
		iMMagick = true;
	}
	else iMMagick = false;
	/* ASC Dialog style */
	infoColor = "#006db0"; /* Honolulu blue */
	instructionColor = "#798541"; /* green_dark_modern (121, 133, 65) AKA Wasabi */
	infoWarningColor = "#ff69b4"; /* pink_modern AKA hot pink */
	infoFontSize = 12;
	Dialog.create("Options for batch DSX conversions \(" + macroL + "\)");
		Dialog.addMessage("Total files in directory = " + count, infoFontSize, infoColor);
		Dialog.addString("Input/output parent directory: ", dir, dir.length + 5);
		Dialog.addString("Subdirectory name for converted files: ", "converted", dir.length);
		Dialog.addRadioButtonGroup("Convert to:", fileTypes, 1, fileTypes.length, "tiff");
		if (iMMagick){
			Dialog.addCheckbox("Also extract height map to 'height' subfolder", true);
			Dialog.addCheckbox("Also create 32-bit height map with micron height values", true);
			Dialog.addCheckbox("Also extract embedded overview thumbnail to 'overview' subfolder", false);
			Dialog.addNumber("JPEG quality:", jpegQual, 0, 3, "");
			Dialog.addNumber("PNG quality:", pngQual, 0, 3, "");
			Dialog.addMessage("Default IM png quality is 75, '7' for compression level 7, '5' for adaptive filtering, \n\(ifThe image has a color map a compression level 7 with no PNG filtering\).", infoFontSize, infoColor);
		}
		else Dialog.addMessage("ImageMagick not found; png and jpeg format conversion will be slower and there will be no height map extraction", infoFontSize, infoWarningColor);
		Dialog.addCheckbox("32-bit images: Stretch viewing contrast range to map range?", true);
		Dialog.addCheckbox("Diagnostic mode", false);
		Dialog.addMessage("For 16-bit height maps, the intensity level to micron conversion factor\nis saved in a file ending '_heightCal.txt'", infoFontSize, infoColor);
	Dialog.show();
		dir = Dialog.getString();
		subDir = Dialog.getString();
		fileType = Dialog.getRadioButton();
		if (iMMagick){
			saveHeight =  Dialog.getCheckbox();
			makeHM32 = Dialog.getCheckbox();
			saveOverview = Dialog.getCheckbox();
			jpegQual = Dialog.getNumber();
			call("ij.Prefs.set", "asc.lastsaved.jpeg.qual", jpegQual);
			pngQual = Dialog.getNumber();
			call("ij.Prefs.set", "asc.lastsaved.png.qual", pngQual);
			if (fileType=="jpeg") iMQualSetting = " -quality " + jpegQual + " ";
			else if (fileType=="png") iMQualSetting = " -quality " + pngQual + " ";
			else iMQualSetting = ""; /* default works OK for most circumstances */
		}
		stretchView32 = Dialog.getCheckbox();
		diagnostics = Dialog.getCheckbox();
	setBatchMode(true);
	if (makeHM32) saveHeight = true;
	if (!endsWith(dir, fS)) outDir = dir + fS + subDir;
	else outDir = dir + subDir;
	processFiles(dir, outDir, fileType);
	setBatchMode("Exit & display");
	statusMessage = "Batch DSX to " + fileType + " conversion of " + count + " files completed";
	if (fileType=="tiff") statusMessage  + = ", scale transferred to converted file";
	showStatus(statusMessage, "flash green");
	beep();wait(400);beep();wait(800);beep();
	call("java.lang.System.gc");
	run("Collect Garbage"); 
	/*
		( 8(|)	( 8(|)	All ASC Functions	@@@@@:-)	@@@@@:-)
	*/		
	function countFiles(dir) {
		list = getFileList(dir);
		for (i=0; i<lengthOf(list); i++) {
			if (endsWith(list[i], "/"))
				countFiles("" + dir + list[i]);
			else count++;
		}
	}
	function processFiles(inPath, outDir, fileType) {
		list = getFileList(dir);
		listLength = list.length;
		for (i=0; i<listLength; i++) {
			 showProgress(i, listLength);
			 if (endsWith(list[i], fS))
					processFiles("" + dir + list[i], outDir, fileType); 
			 else {
				showProgress(n++, count);
				path = dir + list[i];
				processFile(path, outDir, fileType);
			}
		}
	}
	function processFile(inPath, outDir, fileType) {
		/* v230111 Change tag from ImageDataPerPixel (original acquisition) to ColorDataPerPixel (DSX saved resolution). Also changed parseFloat to ParseInt as no decimals needed of pm in a light micrograph!
			v230117 Adds fileType variable.
			v231030 Add use of waitForFile function and skips height maps ifThere is no height layer.
			v231031	Resaves height maps with lateral scales.
			*/
		lcPath = toLowerCase(inPath); /* makes the next line shorter . . .  */
		unit = "um";
		fS = File.separator;
		ext = "." + fileType;
		ext = replace(ext, "tiff", "tif ");
		ext = replace(ext, "jpeg", "jpg");
		if (endsWith(lcPath, ".dsx")) {
			if (!File.exists(outDir )){
				File.makeDirectory(outDir );
				if (!File.exists(outDir)) exit("Unable to create output directory:\n" + outDir);
			}
			if (!endsWith(outDir, fS)) outDir  + = fS;
			newPath = outDir + substring(inPath, lastIndexOf(inPath, fS), lastIndexOf(inPath, ".")) + ext;
			heightLayer = true;
			if (iMMagick) {
				imagePath = inPath + "[0]";
				imExec = "\"" + iMMagickPath + "\" " + "\"" + imagePath + "\" " +  iMQualSetting + " \"" + newPath + "\"";
				if (saveHeight){
					heightDir = outDir + "hm16";
					if (!File.exists(heightDir)) File.makeDirectory(heightDir);
					if (!File.exists(heightDir)) exit("Unable to create output height subdirectory:\n" + heightDir);
					heightPath = inPath + "[2]";
					newHtPath = heightDir + substring(inPath, lastIndexOf(inPath, fS), lastIndexOf(inPath, ".")) + "_hm16" + ext; 
					imHtExec = "\"" + iMMagickPath + "\" " + "\"" + heightPath + "\" " +  iMQualSetting + " \"" + newHtPath + "\"";
					if (diagnostics) IJ.log("IM output command: \n" + imHtExec);
				}
				if (saveOverview){
					ovDir = outDir + "overview";
					if (!File.exists(ovDir)) File.makeDirectory(ovDir);
					if (!File.exists(ovDir)) exit("Unable to create output overview subdirectory:\n" + ovDir);
					ovPath = inPath + "[3]";
					newOvPath = ovDir + substring(inPath, lastIndexOf(inPath, fS), lastIndexOf(inPath, ".")) + "_ov" + ext; 
					imOvExec = "\"" + iMMagickPath + "\" " + "\"" + ovPath + "\" " +  iMQualSetting + " \"" + newOvPath + "\"";
				}
			}		
			if ((fileType=="png" || fileType=="jpeg" || fileType=="bmp" || fileType=="gif ") && iMMagick){				
				showStatus("Saving " + fileType + " using ImageMagick");
				if (diagnostics) IJ.log("IM " + fileType + " image save execString:\n" + imExec);
				exec(imExec);
				if (saveHeight){
					if (diagnostics) IJ.log("IM " + fileType + " height map save execString:\n" + imHtExec);
					exec(imHtExec);
					if (!waitForFile(newHtPath, 10, 0, 2000)){
						statusMessage = newHtPath + " not successfully created, perhaps there is no height layer";
						IJ.log(statusMessage);
						showStatus(statusMessage, "flash red");
						heightLayer = false;
					}
				}
				if (saveOverview){
					if (diagnostics) IJ.log("IM " + fileType + " overview save execString:\n" + imOvExec);
					exec(imOvExec);
				}
			}
			else {
				open(inPath);
				oldFilename = File.name;
				newFilenameWoE = File.nameWithoutExtension;
				newFilename = newFilenameWoE + ext;
				/* note header calibrations are in pm so parseInt is more efficient that parseFloat and does no effect real accuracy */
				metaData = getMetadata("Info");
				umPerPixelX = parseInt(getDSXExifTagFromMetaData(metaData, "ColorDataPerPixelX")) * 10E-7;
				umPerPixelY = parseInt(getDSXExifTagFromMetaData(metaData, "ColorDataPerPixelY")) * 10E-7;
				umPerPixelOrX = parseInt(getDSXExifTagFromMetaData(metaData, "ImageDataPerPixelX")) * 10E-7;
				umPerPixelOrY = parseInt(getDSXExifTagFromMetaData(metaData, "ImageDataPerPixelY")) * 10E-7;
				if (umPerPixelX!=umPerPixelOrX) IJ.log("Note that for " + inPath + " the stored output X scale \(" + umPerPixelX + " microns per pixel\) was different from the original acquisition scale \(" + umPerPixelOrX + " microns per pixel\). The output scale is used.");
				aspectRatio = umPerPixelX/umPerPixelY;
				run("Set Scale...", "distance=1 known=" + umPerPixelX + " pixel=" + aspectRatio + " unit=um");
				/* DSX scale will only be as saved from Olympus app, so no modifications will be necessary */
				imageWidthMicrons = umPerPixelX * Image.width;
				overviewTxt = "Pixel size set from DSX image header: "  + umPerPixelX +  " " + um + "\nAspect ratio: " + aspectRatio + "\nImage width: " + imageWidthMicrons + " " + um;
				IJ.log(overviewTxt);
				if (saveHeight && heightLayer){
					newHeightPath = outDir + substring(inPath, lastIndexOf(inPath, fS), lastIndexOf(inPath, ".")) + "heightCal.txt";
					depthCal = parseInt(getDSXExifTagFromMetaData(metaData, "ColorDataPerPixelZ"));
					if (depthCal<1) depthCal = parseInt(getDSXExifTagFromMetaData(metaData, "HeightDataPerPixelZ"));
					depthCalOr = parseInt(getDSXExifTagFromMetaData(metaData, "ImageDataPerPixelZ"));
					if (depthCal>1 || depthCalOr>1){
						heightString = newHeightPath + ":\n" + overviewTxt + "\n";
						if (depthCal>1){
							heightString  + = "" + d2s(depthCal, 7) + ": Montage Height Map calibration \(pm\/intensity Level\)\n";
							depthCalMicrons = depthCal * 10E-7;
							fullDepthRangeMicrons = d2s(256 * 256 * depthCalMicrons, 5); /* depth map is 16-bit */
							saveHtString  + = "" + d2s(depthCalMicrons, 7) + ": Montage Height Map calibration \(" + um + "\/intensity Level\)\n";
							heightString  + = "" + d2s(fullDepthRangeMicrons, 7) + ": Montage Full 16-bit Height Map Range \(" + um + "\)\n"
						}
						else if (depthCalOr>1){
							heightString  + = "" + d2s(depthCalOr, 7) + ": Original Height Map calibration \(pm\/intensity Level\)\n";
							depthCalMicrons = depthCalOr * 10E-7;
							fullDepthRangeMicrons = d2s(256 * 256 * depthCalMicrons, 5); /* depth map is 16-bit */
							heightString  + = "" + d2s(depthCalMicrons, 7) + ": Original Height Map calibration \(" + um + "\/intensity Level\)\n";
							heightString  + = "" + d2s(fullDepthRangeMicrons, 7) + ": Original Full 16-bit Height Map Range \(" + um + "\)\n";
						}
						while (endsWith(heightString, "\n")) heightString = substring(heightString, 0, lastIndexOf(heightString, "\n"));
						heightCalExportPath = heightDir + newFilenameWoE + "_heightCal.txt";
						File.saveString(heightString, heightCalExportPath);
						if (diagnostics) IJ.log(heightString);
					}
					else IJ.log(oldFilename + ": No height map information found");
				}
				if (diagnostics) IJ.log(macroL + " output directory: " + outDir);
				if (diagnostics) IJ.log("Converted file: " + newFilename);
				saveAs(fileType, newPath);
				if (iMMagick){
					if (saveHeight){
						if (diagnostics) IJ.log("IM " + fileType + " height map save execString:\n" + imHtExec);
						exec(imHtExec);
						if (!waitForFile(newHtPath, 10, 0, 2000)){
							IJ.log(newHtPath + " not successfully created, perhaps there is no height layer");
							heightLayer = false;
						}
						if (!makeHM32){
							open(newHtPath);
							run("Set Scale...", "distance=1 known=" + umPerPixelX + " pixel=" + aspectRatio + " unit=um");
							saveAs("tiff", newHtPath);
							close();
						}
					}
					if (saveOverview){
						if (diagnostics) IJ.log("IM " + fileType + " overview save execString:\n" + imOvExec);
						exec(imOvExec);
					}					
				}
				if (makeHM32 && heightLayer){
					nTitle32 = "" + File.nameWithoutExtension + "_HMCal_in_" + um;
					heightDir32 = outDir + "hm_32bit";
					if (!File.exists(heightDir32)) File.makeDirectory(heightDir32);
					newHtPath32 = heightDir32 + substring(inPath, lastIndexOf(inPath, fS), lastIndexOf(inPath, ".")) + "_HMCal_in_" + um + ext; 
					if (File.exists(newHtPath)) open(newHtPath);
					else exit(newHtPath + " not found so unable to create height-calibrated 32-bit image");
					run("Set Scale...", "distance=1 known=" + umPerPixelX + " pixel=" + aspectRatio + " unit=um");
					saveAs("tiff", newHtPath);
					rename(nTitle32);
					run("32-bit");
					run("Multiply...", "value=" + depthCalMicrons);
					if (stretchView32) run("Enhance Contrast...", "saturated=0");
					saveAs("tiff", newHtPath32);
					close();
				} 
				if (getImageID()!=orImageID) close(); /* keep original image open */
			}
		}
	}
	function findAppPath(appName, appEx, defaultPath) {
		/* v210921 1st version: appName is assumed to be the app folder name, appEx is the executable, default is the default return value
			v211018: assumes specif ic executable path stored in prefs Prints message rather than exits when app not found
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
		appLoc = "" + fS + appName + fS + appEx;
		cProg = "C:" + fS + "Program Files";		
		defAppPaths = newArray(cProg + fS + "Utilities" + appLoc, cProg + " \(x86\)" + fS + "Utilities" + appLoc, cProg + appLoc, cProg + " \(x86\)" + appLoc, appsPath + appLoc, ijPath + "Apps" + appLoc);
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
			Dialog.addFile("Locate " + appEx + ":", "C:" + fS + "Program Files");
			Dialog.addMessage("iffound, the location will be saved in prefs for future use:\n" + prefsName);
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
	function getDSXExifTagFromMetaData(metaData, tagName) {
	/* metaData is string generated by metaData = getMetadata("Info");	
		v230120: 1st version  version b
	*/
		i0 = indexOf(metaData, "<" + tagName + ">");
		if (i0!=-1) {
			i1 = indexOf(metaData, "</" + tagName + ">", i0);
			tagLine = substring(metaData, i0, i1);
			tagValue = substring(tagLine, indexOf(tagLine, ">") + 1, tagLine.length);
		}
		else tagValue = "" + tagName + " not found in metaData";
		return tagValue;
	}
	function waitForFile(filePath, testWait, minWait, maxWait) {
		/* All times in mS
		v230711: 1st version
		v231030: Restored missing '=' */
		wait(minWait);
		maxIterations = maxWait/testWait;
		for (i=0, fileFound=false; i<maxIterations; i++){
			showProgress(i, maxIterations);
			showStatus("Waiting for " + filePath);
			if (!File.exists(filePath)) wait(testWait);
			else {
				fileFound = true;
				IJ.log(filePath + " found after waiting " + i*testWait + " mS");
				i = maxIterations;
			}
		}
		return fileFound;
	}