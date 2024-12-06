/* Generate ImageJ/Fiji stitching configuration file directory of DSX images
	Two versions of this macro are provided, corresponding to the 2 available versions ("new"  and "old") of the Fiji stitching plugin by Preibisch et al.: Please note that the Stitching plugins available through Fiji, are based on a publication:
	Preibisch, S., Saalfeld, S., & Tomancak, P. (2009). Globally optimal stitching of tiled 3D microscopic image acquisitions. Bioinformatics, 25(11), 1463–1465. doi:10.1093/bioinformatics/btp184
	and the authors request citation if they are used successfully. More information: https://imagej.net/plugins/image-stitching
	
	This macro requires that the exifReader plugin has previously been installed: https://imagej.net/plugins/exif-reader.html

	v230201: 1st version   Peter J. Lee  Applied Superconductivity Center  NHMFL FSU
	v230202-6: Adds more option including just stitching a limited number of initial tiles (useful for checking overlap).
	v230208: Adds scale from DSX header.
	v230220: Updates tileCount for filter.
	v230308: Allows different x and Y overlaps.
	v230315: Multiple sets fixed.
	v230404: Faster with batchmode applied.
	v230421: Scale imported for each set instead of using initial image.
	v230510: Accepts non-square pixels.
	v230511b: Added waitForOpenWindow and safeSaveandClose functions. f1: updated getExifData function.
	v230513: Uses IsMonochrome setting. Adds transfer of metaData option.
	v230515: Checks for different overlap in selected set.
	v230522: Reworks the getExifData function.
	v230526: Can use stage positions instead of overlaps. getDSXExifTagFromMetaData function modified so it finds the true stage positions. batchmode off before save.
	v230609: Checks to see if any tiles were not matched.
	v230615: Should work with TIFF files again.
	v230807: Spelling corrections and more information in main dialog.
	v230808b: Migrates to newer Grid/Collection Stitching plugin. F1: Updated sensible units function 230809.
	v230810: Fixed registered file name version variation issue. Composite convert option works for both RGB and gray (fixed in v230811). Tweaks to dialog text.
	v230812: Added areaFractionBlend (although it doesn't seem to do much). Removed irrelevant options.
	v230814: no attempt to save blend if 'Do not fuse...' option selected. Updated safeSaveAndClose function.
	v230822: Corrected selectImage to selectWindow. F1: Updated indexOfArray functions. F2: Updated to safeSaveAndClose_v230815.
	v231020: Minor dialog tweak.
	v231114: Changes related to waitForOpenWindow. F1: Updated sensibleUnits function and removed now-redundant indexOfArray function.
	v240222: Improved grammar, added toolbar flashes.
	v240227: Saved path of registered position file to prefs. F1: Update safeSaveAndClose.
	*/
	macroL = "IJStitch_DSX_Mosaic_From_Selected_Image(new_plugin)_v240227-f1.ijm";
	prefsNameKey = "asc.IJStitch.Prefs.";
	if (nImages<1){
		open(File.openDialog("This macro currently requires an open DSX image, please select one"));
		if (nImages<1) exit("This macro currently requires an open DSX image");
	}
	orImageID = getImageID();
	fileName = getInfo("image.filename");
	fWOE = File.getNameWithoutExtension(fileName);
	ext = substring(fileName, fWOE.length+1);
	dir = getInfo("image.directory");
	// allowableFormats = newArray("dsx", "tif", "png", "jpeg");
	foundDSXMapFiles = getDSXPanoFilesWithSameExtension(dir, ext);
	if (foundDSXMapFiles.length<1) exit("No tiles were found");
	dsxEXIFData = getExifData(dir + foundDSXMapFiles[0]);
	tileCount =  foundDSXMapFiles.length;
	if (tileCount<2) exit("Only found " + tileCount + "files; that is not enough to create a panorama");
	dirF = substring(dir, 0, dir.length-1);
	micronS = getInfo("micrometer.abbreviation");
	fS = File.separator();
	bits = bitDepth();
	//Array.print(foundDSXMapFiles);
	mapSets = getUniqueElementPrefixes(foundDSXMapFiles, "_X");
	mapSetsL = mapSets.length;
	if(mapSetsL==0) exit("No DSX Mosaic files found");
	infoColor = "#0076B6";
	leq = fromCharCode(0x2264);
	infoFontSize = 11.5;
	reportLog = "";
	Dialog.create("DSX IJ Stitch Options \(" + macroL + "\)");
		Dialog.addHelp("https://imagej.net/plugins/image-stitching");
		// Dialog.addMessage("Total DSX mosaic files in directory = " + tileCount, 11.5, infoColor);
		dirL = lengthOf(dir);
		Dialog.addString("Input/output directory:", dir, minOf(62, lengthOf(dir)+5));
		if (dirL>62){
			Dialog.setInsets(-5, 0, 0);
			Dialog.addMessage("Path: " + dir, minOf(infoFontSize, 1000/dirL), infoColor);
		} 
		if (mapSetsL>1) {
			defRows =  minOf(mapSetsL, 3);
			Dialog.addRadioButtonGroup("Choose map set:", mapSets, defRows, round(mapSetsL/defRows), mapSets[0]);
		}
		tileListMessage = "";
		for (i=0;i<mapSetsL;i++){
			tileListMessage += mapSets[i] + ": total tiles in set: " + countArrayElementsWithString(foundDSXMapFiles, mapSets[i]) + " out of " + tileCount + " DSX files in directory";
			if(i+1<mapSetsL) tileListMessage += "\n";
		} 
		Dialog.addMessage(tileListMessage, infoFontSize, infoColor);
		Dialog.addNumber("Stitch 1st 'n' tiles only:", 0, 0, 4, "tiles \(leave as '0' for all\)");
		overlapX = parseInt(getDSXExifTagFromMetaData(dsxEXIFData, "OverlapSize", true));
		if (overlapX<=10) overlapX = call("ij.Prefs.get", prefsNameKey+"overlapX", 20);
		Dialog.addNumber("Overlap X\(Y\) ", overlapX, 0, 3, "% \(also Y overlap if no value entered below\)");
		Dialog.addNumber("Overlap Y*", "", 0, 3, "% *\(leave blank if the same as X\)");
		if (overlapX<=10) useStagePosn = true;
		else useStagePosn = false;
		Dialog.addCheckbox("Use actual stage positions instead of overlap \(default if overlap " + leq + "10\)", useStagePosn);
		message = "Default options not set in this version: channels_for_registration=[Red, Green and Blue] rgb_order=rgb";
		message += "\n                  'subpixel_accuracy' and 'Save computation time' options will be used because why not?";
		message += "\n                  List tiles row-by-row \(DSX list is column-by-column\)";
		message += "\n                  Compute overlap \(otherwise would use approximate grid coordinates\)";
		Dialog.addMessage(message, infoFontSize, infoColor);
		blendingOptions = newArray("Linear Blending", "Average", "Median", "Max. Intensity", "Min. Intensity", "Do not fuse images \(only write TileConfiguration\)");
		blendingTxt = "Linear Blending: \tIn the overlapping area, the intensities are smoothly adjusted between overlapping images.\n";
		blendingTxt += "Average: \tIn the overlapping area, the average intensity of all overlapping images is used.\n";
		blendingTxt += "Median: \tIn the overlapping area, the median intensity of all overlapping images is used.\n";
		blendingTxt += "Max. Intensity: In the overlapping area, the maximum intensity between all overlapping images is used.\n";
		blendingTxt += "Min. Intensity: In the overlapping area the minimum intensity between all overlapping images is used.\n"
		blendingTxt += "Overlay into Composite: all channels of all input images will be put into the output image as separate channels\n";
		blendingTxt += "Do not fuse images: no output images will be computed, just the overlap is computed";
		Dialog.addMessage(blendingTxt, infoFontSize, infoColor);
		blendingOption = call("ij.Prefs.get", prefsNameKey+"blending", "Linear Blending");
		Dialog.addChoice("Blending:", blendingOptions, blendingOption);
		// Dialog.addRadioButtonGroup("Blending:", blendingOptions, 1, blendingOptions.length, blendingOptions[0]);
		Dialog.addNumber("Fusion value:", 1.5, 1, 4, "1.5 default, no documentation, weird results >7");
		Dialog.addNumber("Regression value:", 0.3, 1, 4, "Assumed non-overlapping if below this. 'Good' values are typically >0.7");
		Dialog.addNumber("max/avg:", 3.5, 1, 4, "Default threshold error for discarding is 2.5");
		Dialog.addNumber("Absolute value:", 3.5, 1, 4, "Links removed if the absolute displacement is greater \(default 3.5\)");
		fusionAreas = Array.resample(Array.getSequence(2), 11);
		Dialog.addRadioButtonGroup("Blended Area Fraction, TBH this doesn't seem to have much impact \(default is 0.2\):", fusionAreas, 1, 5, "0.2");
		if (toLowerCase(getDSXExifTagFromMetaData(dsxEXIFData, "IsMonochrome", true))=="true") isMonochrome = true;
		else isMonochrome = false;
		if (isMonochrome) Dialog.addCheckbox("Open image was acquired as monochrome; convert stitched image to 8-bit grayscale?", true);
		Dialog.addCheckbox("Check for unregistered tiles and save config file for missing files", true);
		checkboxOptions = newArray("Copy 1st tile metadata to stitched image?", "Decompose composite output", "Diagnostic output");
		checkboxDefaults = newArray(true, true, false);
		if(getSliceNumber()>1){
			if (Stack.isHyperstack){
				hyper = true;
				checkboxOptions = Array.concat("Add tiles as ROIs?", checkboxOptions);
				checkboxDefaults = Array.concat(true, checkboxDefaults);
			} 
		}
		else hyper = false;
		rowN = 2;
		colN = Math.ceil(checkboxOptions.length/rowN);
		Dialog.addCheckboxGroup(rowN, colN, checkboxOptions, checkboxDefaults);
		Dialog.addMessage("Use separate 'Stitch height-map from Registered Stitch Coords macro to assemble corresponding height-maps", infoFontSize, infoColor);
	Dialog.show();
		dir = Dialog.getString();
		if (mapSetsL==1) prefixF = mapSets[0];
		else prefixF = Dialog.getRadioButton();
		tileMax = countArrayElementsWithString(foundDSXMapFiles, prefixF);
		nTileLimit = Dialog.getNumber();
		if (nTileLimit==0) tileLimit = tileMax;
		else tileLimit = minOf(nTileLimit, tileMax);
		overlapX = minOf(90, Dialog.getNumber());
		call("ij.Prefs.set", prefsNameKey+"overlapX", overlapX);
		overlapY = Dialog.getNumber();
		if (isNaN(overlapY)) overlapY = overlapX;
		else overlapY = minOf(90, overlapY);
		useStagePosn = Dialog.getCheckbox();
		rowByRow = true; /* simplified by this not being optional for this version */
		computeOverlap = true; /* simplified by this not being optional for this version */
		blendingOption = Dialog.getChoice();
		call("ij.Prefs.set", prefsNameKey+"blending", blendingOption);
		fusionVal = Dialog.getNumber();
		regressionVal = Dialog.getNumber();
		maxAvgVal = Dialog.getNumber();
		absVal = Dialog.getNumber();
		fusionFraction = Dialog.getRadioButton();
		bshScript = "mpicbg.stitching.fusion.BlendingPixelFusion.fractionBlended = " + fusionFraction;
		IJ.log("Temporary fractionBlend applied:")
		eval("bsh", bshScript);
		if (isMonochrome){
			if (Dialog.getCheckbox()) grayConvert = true;
		}
		else grayConvert = false;
		checkForMissingTiles = Dialog.getCheckbox();
		if (hyper) addROIs = Dialog.getCheckbox();
		else addROIs = false;
		transferMetadata = Dialog.getCheckbox();
		compoConvert = Dialog.getCheckbox();
		diagnostics = Dialog.getCheckbox();
	setBatchMode(true);
	if (diagnostics) IJ.log("prefix chosen: " + prefixF + ", X overlap: " + overlapX + ", Y overlap: " + overlapY);
	xMax = 0;
	yMax = 0;
	suffixF = "." + ext;
	tileXs = newArray();
	tileYs = newArray();
	filteredDSXMapFiles = newArray();
	for (i=0, filteredTileCount=0;i<tileCount && filteredTileCount<tileLimit;i++){
		imageT = foundDSXMapFiles[i];
		if(startsWith(imageT, prefixF)){
			filteredDSXMapFiles[filteredTileCount] = imageT;
			if (filteredTileCount==0){
				pSX =  lastIndexOf(imageT, "_X") + 2;
				pSY =  lastIndexOf(imageT, "_Y") + 2;
				digitN = abs(pSY-pSX) - 2;
			}
			tileXs[filteredTileCount] = parseInt(substring(imageT, pSX, pSX+digitN));
			xMax = maxOf(xMax, tileXs[filteredTileCount]);
			tileYs[filteredTileCount] = parseInt(substring(imageT, pSY, pSY+digitN));
			yMax = maxOf(yMax, tileYs[filteredTileCount]);
			filteredTileCount++;
		}
	}
	tileN = filteredDSXMapFiles.length;
	if(rowByRow){
		lineByLineOrder = newArray();
		for (i=0;i<filteredTileCount;i++)
			lineByLineOrder[i] = (tileYs[i]-1)*yMax + tileXs[i]-1;
		Array.sort(lineByLineOrder, filteredDSXMapFiles, tileXs, tileYs);
	}
	tileConfig = "# Define the number of dimensions we are working on\ndim = 2\n\n# Define the image coordinates\n";
	tileConfigFP = tileConfig;
	for (i=0;i<tileN;i++){
		showProgress(i, tileN);
		showStatus("Extracting image information");
		if (i==0){
			dsxEXIFData = getExifData(dir + filteredDSXMapFiles[i]);
			if (toLowerCase(getDSXExifTagFromMetaData(dsxEXIFData, "IsMonochrome", true))=="true") isMonochrome = true;
			else isMonochrome = false;
			if (isMonochrome && grayConvert) grayConvert = true;
			else grayConvert = false;
			scaleImageTitle = filteredDSXMapFiles[i];
			if (toLowerCase(ext)=="dsx"){
				umPerPixelX = parseFloat(getDSXExifTagFromMetaData(dsxEXIFData, "ColorDataPerPixelX", true)) * 10E-7;
				umPerPixelY = parseFloat(getDSXExifTagFromMetaData(dsxEXIFData, "ColorDataPerPixelY", true)) * 10E-7;
				umPerPixelOrX = parseFloat(getDSXExifTagFromMetaData(dsxEXIFData, "ImageDataPerPixelX", true)) * 10E-7;
				umPerPixelOrY = parseFloat(getDSXExifTagFromMetaData(dsxEXIFData, "ImageDataPerPixelY", true)) * 10E-7;
				overlapXCheck = parseInt(getDSXExifTagFromMetaData(dsxEXIFData, "OverlapSize", true));
				if (prefixF!=mapSets[0]){  /* Just in case the overlap is different within the folder */
					if (overlapX!=overlapXCheck){
						Dialog.create(macroL + ": Overlap mismatch check"){
							Dialog.addMessage("File overlap from header = " + overlapXCheck);
							Dialog.addNumber("Overlap \(X overlap if Y value entered below\)", overlapX, 0, 3, "%");
							Dialog.addNumber("Overlap Y \(if X and Y overlaps are different only\)", "", 0, 3, "%");
						Dialog.show();
							overlapX = minOf(90, Dialog.getNumber());
							call("ij.Prefs.set", prefsNameKey+"overlapX", overlapX);
							overlapY = Dialog.getNumber();
							if (isNaN(overlapY)) overlapY = overlapX;
							else overlapY = minOf(90, overlapY);
						}
					}
				}
				calRat = umPerPixelX/umPerPixelOrX;
				if (calRat>1.001 || calRat<0.999) IJ.log("Note that for " + filteredDSXMapFiles[i] + " the stored output X scale \(" + umPerPixelX + " microns per pixel\) was different from the original acquisition scale \(" + umPerPixelOrX + " microns per pixel\). The output scale is used.");
				pixelW = umPerPixelX;
				pixelH = umPerPixelY;
				unit = micronS;
				microscopeSettings = "DSX settings:\n";
				refCodes = newArray("OverlapSize", "StitchingRowCount", "StitchingColumnCount", "ExtendMode", "ZRangeMode", "ZSliceTotal", "ZSliceCount", "ZStartPosition", "ZEndPosition", "ZRange", "ZPitchTravel", "StagePositionX", "StagePositionY", "ObjectiveLensID", "ObjectiveLensType", "ObjectiveLensMagnification", "ZoomMagnification", "OpiticalZoomMagnification", "DigitalZoomMagnification", "MapRoiTop", "MapRoiLeft", "MapRoiWidth", "MapRoiHeight", "ImageAspectRatio", "ImageTrimmingSize");
				for (r=0;r<refCodes.length;r++) microscopeSettings += refCodes[r] + ": " + getDSXExifTagFromMetaData(dsxEXIFData, refCodes[r], true) + "\n";
				if (diagnostics) IJ.log(microscopeSettings);
				File.saveString(microscopeSettings, dir + File.getNameWithoutExtension(filteredDSXMapFiles[i]) + "_microscopeSettings.txt");
				if (useStagePosn){
					stageX0um = parseInt(getDSXExifTagFromMetaData(dsxEXIFData, "StagePositionX", true)) * 10E-4; /* stage positions are in nm not pm */
					stageY0um = parseInt(getDSXExifTagFromMetaData(dsxEXIFData, "StagePositionY", true)) * 10E-4;
					tileXs[i] = 0;
					tileYs[i] = 0;
					fileString = filteredDSXMapFiles[i] + "\; \; \(0, 0\)\n";
					tileConfig += "" + fileString;
					tileConfigFP += "" + dir + fileString;
				}
			}
			else getVoxelSize(pixelW, pixelH, voxelDepth, unit);
			if(unit!="pixels"){
				newPixelWidthNewUnits = sensibleUnits(pixelW, unit);
				newPixelHeightNewUnits = sensibleUnits(pixelH, unit);
				pixelW = newPixelWidthNewUnits[0];
				pixelH = newPixelHeightNewUnits[0];
				unit = newPixelWidthNewUnits[1];
			}
			aspectRatio = pixelW/pixelH;
			imageWidth = Image.width;
			imageHeight = Image.height;
			run("Set Scale...", "distance=1 known=&pixelW pixel=&aspectRatio unit=&unit");
			reportLog = "Image used for scale: " + scaleImageTitle + " \(pixel width = " + pixelW + " " + unit + ", aspect ratio = " + aspectRatio + "\), "
				+ imageWidth + " x " + imageHeight + " pixels";
			if (useStagePosn)	reportLog += ", stage positions used for tile positions";
			else {
				overlapAdvX = imageWidth * (100-overlapX) /100;
				overlapAdvY = imageHeight * (100-overlapY) /100;	
				reportLog += ", x advance = " + overlapAdvX;
				if (overlapAdvX!=overlapAdvY) reportLog += ", y advance = " + overlapAdvY;
			}
		}
		else if (useStagePosn){
				dsxEXIFDataTemp = getExifData(dir + filteredDSXMapFiles[i]);
				stageXum = parseInt(getDSXExifTagFromMetaData(dsxEXIFDataTemp, "StagePositionX", true)) * 10E-4;
				stageYum = parseInt(getDSXExifTagFromMetaData(dsxEXIFDataTemp, "StagePositionY", true)) * 10E-4;
				if (diagnostics){
					IJ.log("stageXum, stageXum-stageX0um, stageXum-stageX0um/pixelW, stageYum-stageY0um/pixelH");
					IJ.log(stageXum+", "+stageXum-stageX0um+", "+(stageXum-stageX0um)/pixelW+", "+(stageYum-stageY0um)/pixelH);
				}
				tileXs[i] = abs((stageXum - stageX0um) / pixelW);
				tileYs[i] = abs((stageYum - stageY0um) / pixelH);
				fileString = filteredDSXMapFiles[i] + "\; \; \(" + d2s(tileXs[i], 1) + ", " +  d2s(tileYs[i], 1) + "\)\n";
				tileConfig += "" + fileString;
				tileConfigFP += "" + dir + fileString;
		}
		if (!useStagePosn){
			fileString = filteredDSXMapFiles[i] + "\; \; \(" + d2s((tileXs[i]-1)*overlapAdvX, 0) + ", " +  d2s((tileYs[i]-1)*overlapAdvY, 0) + "\)\n";
			tileConfig += "" + fileString;
			tileConfigFP += "" + dir + fileString;
		}
	}
	if (reportLog!= "") IJ.log(reportLog);
	run("Set Scale...", "distance=1 known=&pixelW pixel=&aspectRatio unit=&unit");
	title1FP = prefixF + "_Full-Path-TileConfiguration";
  	title2FP = "["+title1FP+"]";
 	f = title2FP;
  	if (isOpen(title1FP))  print(f, "\\Update:"); // clears the window
  	else run("Text Window...", "name="+title2FP+" width=72 height=8 menu");
	if (diagnostics) IJ.log("Full path tile configuration:\n" + tileConfigFP);
 	print(f, tileConfigFP);
	configFPPath = dir + title1FP +".txt";
	saveAs("Text", configFPPath); /* Saved for compatibility with older versions */
	run("Close"); /* Need to close window and start fresh as there is no rename function for text windows */
	title1 = prefixF + "_TileConfiguration";
	title2 = "["+title1+"]";
	f = title2;
  	if (isOpen(title1)) print(f, "\\Update:"); // clears the window
  	else run("Text Window...", "name="+title2+" width=72 height=8 menu");
	if (diagnostics) IJ.log("Tile configuration:\n" + tileConfig);
	print(f, tileConfig);
	configPath = dir + title1 +".txt";
	saveAs("Text", configPath);
	run("Close");
	if (addROIs) optionROIs = " add_tiles_as_rois";
	else optionROIs = " ";
	stitchOptions = "type=[Positions from file] order=[Defined by TileConfiguration] directory=[&dir] layout_file="+title1+".txt fusion_method=[&blendingOption] fusion="+fusionVal+" regression_threshold="+regressionVal+" max/avg_displacement_threshold="+maxAvgVal+" absolute_displacement_threshold="+absVal+optionROIs+ " compute_overlap ignore_z_stage subpixel_accuracy computation_parameters=[Save computation time (but use more RAM)] image_output=[Fuse and display]";
	run("Grid/Collection stitching", stitchOptions);
	if(diagnostics) IJ.log("Stitch commands:\n" + stitchOptions);
	nTitle = prefixF + "_IJ-Stitch";
	if (!startsWith(blendingOption, "Do not")){
		waitForOpenWindow("Fused", 500, 1000, 1000 * tileN);
		selectWindow("Fused");
		rename(nTitle);
		run("Set Scale...", "distance=1 known=&pixelW pixel=&aspectRatio unit=&unit");
		if (grayConvert) run("8-bit");
		if (transferMetadata) setMetadata("Info", dsxEXIFData);
	}
	if (checkForMissingTiles){
		regFileVariants = newArray(".registered", ".registered.txt", "txt.registered");
		for (i=0, regFileFound=false; i<regFileVariants.length && regFileFound==false; i++){
			if (File.exists(configPath + regFileVariants[i])){
				regFilePath = configPath + regFileVariants[i];
				regFileFound = true;
			}
		}
		if (regFileFound){
			registeredString = File.openAsString(regFilePath);
			firstIJSHeaderLine = "# Define the number of dimensions we are working on";
			lastIJSHeaderLine = "# Define the image coordinates\n";
			if (indexOf(registeredString, firstIJSHeaderLine)==0) regType = "ijSReg";
			else exit("Registration file does does not have the expect first line of a registered IJS file");
			headerText = firstIJSHeaderLine + "\ndim = 2\n\n" + lastIJSHeaderLine;
			iLastIJSHeaderLine = indexOf(registeredString, lastIJSHeaderLine)+lastIJSHeaderLine.length;
			if (iLastIJSHeaderLine<0) exit("Expected header line not found: " + lastIJSHeaderLine);
			fileLineList = substring(registeredString, iLastIJSHeaderLine);
			iFile = 0;
			prePath = "";
			fileLines = split(fileLineList, "\n");
			regLN = fileLines.length;
			registeredFiles = newArray();
			for(i=0; i<regLN; i++){
				showProgress(i, regLN);
				registeredFiles[i] = prePath + substring(fileLines[i], iFile, indexOf(fileLines[i], ";"));
			}
			missingTiles = newArray();
			missedXMax = 0;
			missedYMax = 0;
			missedXMin = xMax;
			missedYMin = yMax;
			reTileConfig = "# Define the number of dimensions we are working on\ndim = 2\n\n# Define the image coordinates\n";
			reTileConfigFP = reTileConfig;
			for(i=0, mTileN=0; i<tileN; i++){
				showProgress(i, tileN);
				iReg = indexOfArrayThatContains(registeredFiles, filteredDSXMapFiles[i], -1);
				if (iReg<0){
					missingTiles[mTileN] = filteredDSXMapFiles[i];
					if (diagnostics) IJ.log(filteredDSXMapFiles[i] + " not found in registered list");
					if (useStagePosn){
							dsxEXIFDataTemp = getExifData(dir + filteredDSXMapFiles[i]);
							stageXum = parseInt(getDSXExifTagFromMetaData(dsxEXIFDataTemp, "StagePositionX", true)) * 10E-4;
							stageYum = parseInt(getDSXExifTagFromMetaData(dsxEXIFDataTemp, "StagePositionY", true)) * 10E-4;
							if (diagnostics){
								IJ.log("stageXum, stageXum-stageX0um, stageXum-stageX0um/pixelW, stageYum-stageY0um/pixelH");
								IJ.log(stageXum+", "+stageXum-stageX0um+", "+(stageXum-stageX0um)/pixelW+", "+(stageYum-stageY0um)/pixelH);
							}
							tileXs[i] = abs((stageXum - stageX0um) / pixelW);
							tileYs[i] = abs((stageYum - stageY0um) / pixelH);
							fileString = filteredDSXMapFiles[i] + "\; \; \(" + d2s(tileXs[i], 1) + ", " +  d2s(tileYs[i], 1) + "\)\n";
							reTileConfig += "" + fileString;
							reTileConfigFP += "" + dir + fileString;
					}
					else {
						fileString = filteredDSXMapFiles[i] + "\; \; \(" + d2s((tileXs[i]-1)*overlapAdvX, 0) + ", " +  d2s((tileYs[i]-1)*overlapAdvY, 0) + "\)\n";
						reTileConfig += "" + fileString;
						reTileConfigFP += "" + dir + fileString;				
					} 
					missedXMax = maxOf(missedXMax, tileXs[i]);
					missedYMax = maxOf(missedYMax, tileYs[i]);
					missedXMin = minOf(missedXMin, tileXs[i]);
					missedYMin = minOf(missedYMin, tileYs[i]);
					mTileN++;
				}
				else if (diagnostics) IJ.log(filteredDSXMapFiles[i] + " found in registered list index: " + iReg);
			}
			if (mTileN>0) {
				title1 = prefixF + "_Missed_TileConfiguration";
				title2 = "["+title1+"]";
				f = title2;
				reConfigPath = dir + title1 +".txt";	
				if (isOpen(title1))
					 print(f, "\\Update:"); // clears the window
				else run("Text Window...", "name="+title2+" width=72 height=8 menu");
				print(f, reTileConfig);
				saveAs("Text", reConfigPath);
				run("Close");
				title1 = prefixF + "_Missed_Full-Path-TileConfiguration";
				title2 = "["+title1+"]";
				f = title2;
				reConfigPathFP = dir + title1 +".txt";	
				if (isOpen(title1))
					 print(f, "\\Update:"); // clears the window
				else run("Text Window...", "name="+title2+" width=72 height=8 menu");
				print(f, reTileConfigFP);
				saveAs("Text", reConfigPathFP);
				run("Close");
				IJ.log(mTileN + " tiles missing from registration:\n" + reTileConfig + "\n" + reTileConfigFP);
				IJ.log("Missing tile range: X" + missedXMin + "-" + missedXMax + " Y" + missedYMin + "-" + missedYMax);
				IJ.log("Rerun config paths \(Missing tiles only\): " + reConfigPath + "\n" + reConfigPathFP);
			}
			else IJ.log("All " + tileN + " tiles were successfully registered");
			if (diagnostics) IJ.log(tileN + ": filtered tiles\n" + regLN + ": registered entries\n" + mTileN + ": missing tiles");
		}
		else IJ.log("Registration file for missing files not found");
	}
	if (!startsWith(blendingOption, "Do not")) {
		selectWindow(nTitle);
		if (is("composite") && compoConvert){
			compoID = getImageID();
			if (is("grayscale") && grayConvert) run("Z Project...", "projection=[Average Intensity]");
			else run("Stack to RGB");
			convID = getImageID();
			selectImage(compoID);
			close();
			selectImage(convID);
		} 
		safeSaveAndClose("tiff", dir, nTitle + ".tif", false);
	}
	else IJ.log(macroL + " completed, 'Do not fuse' selected");
	call("ij.Prefs.set", "asc.stitch.helpers.lastPositionFile", regFilePath); 	
	if (is("Batch Mode")) setBatchMode("exit & display");
	call("java.lang.System.gc");
	run("Collect Garbage"); 
	// IJ.log("Stitch commands:\n" + stitchOptions);
	showStatus("Completed macro: " + macroL, "flash green");
	/* End of Stitch_DSX_Mosaic_Using_Selected_Image_and_All_Others_in_Same_Directory macro */
	/*
		( 8(|)	( 8(|)	Required Functions	@@@@@:-)	@@@@@:-)
	*/
	function countArrayElementsWithString(thisArray, stringIn){
		for(i=0, c=0;i<thisArray.length;i++) if(indexOf(thisArray[i], stringIn)>=0) c++;
		return c;
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
	function indexOfArrayThatContains(array, value, default) {
		/* Like indexOfArray but partial matches possible
			v190423 Only first match returned, v220801 adds default.
			v230902 Limits default value to array size */
		indexFound = minOf(lengthOf(array) - 1, default);
		for (i=0; i<lengthOf(array); i++){
			if (indexOf(array[i], value)>=0){
				indexFound = i;
				i = lengthOf(array);
			}
		}
		return indexFound;
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