/* Copy Olympus DSX 3D-projection from system Clipboard, remove border, remove excess background space
	v230217: 1st version  Peter J. Lee  Applied Superconductivity Center, National High Magnetic Field Laboratory, FSU
*/
macroL = "DSX_3D_Projection_from_SystemClipBoard_to_Cropped_Image_v230217.ijm";
run("System Clipboard");
doWand(20, 20);
run("Crop");
run("Select None");
run("Select Bounding Box (guess background color)");
run("Enlarge...", "enlarge=30");
run("Crop");
rename("DSX_3D_Projection");