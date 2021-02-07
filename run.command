#!/bin/bash

function usage {
	cat << EOM
Usage: $(basename "$0") [OPTION]...
	-h	help
	-a value		your Apple ID
	-n value		appName or path
	-p value		app specifired password
	-t value		title of installer
	-i value		identifier (ex. com.example.appname)
	-v value		version (ex. 1.0.0)
	-d value		Developer ID Application (ex "Developer ID Installer: <Your Name> (XXXXXXXXXX)" ) 
	-e value		Developer ID Installer (ex "Developer ID Installer: <Your Name> (XXXXXXXXXX)" )
	
	for example
	$(basename "$0") -a "YourAppleID" -n "emptyExample" -p "xxxx-xxxx-xxxx-xxxx" -t "Empty Example" -i "com.example.emptyExample" -v "1.0.0" -da "Developer ID Installer: <Your Name> (XXXXXXXXXX)" -di "Developer ID Installer: <Your Name> (XXXXXXXXXX)" 
EOM
}

appleId=""
appName=""
workingDir=""
appPass=""
installerTitle=""
identifier=""
version=""
developerIDApplication=""
developerIDInstaller=""

while getopts ":a:n:p:t:i:v:d:e:h" optKey; do
	case "$optKey" in
		a)
			appleId=${OPTARG}
			echo "appleId $appleId"
			;;
		n)
			appNameWithExt=$(basename "${OPTARG}")
			appName=${appNameWithExt%\.*}
			workingDir=$(dirname "${OPTARG}")
			echo "appNameWithExt $appNameWithExt"
			echo "appName $appName"
			echo "workingDir $workingDir"
			;;
		p)
			appPass=${OPTARG}
			echo "appPass $appPass"
			;;
		t)
			installerTitle=${OPTARG}
			echo "installerTitle $installerTitle"
			;;
		i)
			identifier=${OPTARG}
			echo "identifier $identifier"
			;;
		v)
			version=${OPTARG}
			echo "version $version"
			;;
		d)
			developerIDApplication=${OPTARG}
			echo "developerIDApplication $developerIDApplication"
			;;
		e)
			developerIDInstaller=${OPTARG}
			echo "developerIDInstaller $developerIDInstaller"
			;;
		h)
			usage
			;;
	esac
done

# check options
optionOk=0
if [ "$appleId" == "" ] ; then
	echo "Error no option: -a <YourAppleID>"
	optionOk=1
fi
if [ "$appName" == "" ] ; then
	echo "Error no option: -n <appName>"
	optionOk=1
fi
if [ "$appPass" == "" ] ; then
	echo "Error no option: -p <appPass>"
	optionOk=1
fi
if [ "$installerTitle" == "" ] ; then
	echo "Error no option: -t <installerTitle>"
	optionOk=1
fi
if [ "$identifier" == "" ] ; then
	echo "Error no option: -i <identifier>"
	optionOk=1
fi
if [ "$version" == "" ] ; then
	echo "Error no option: -v <version>"
	optionOk=1
fi
if [ "$developerIDApplication" == "" ] ; then
	echo "Error no option: -d <developerIDApplication>"
	optionOk=1
fi
if [ "$developerIDInstaller" == "" ] ; then
	echo "Error no option: -e <developerIDInstaller>"
	optionOk=1
fi
if [ $optionOk -eq 0 ] ;then
	echo "options ok"
else
	echo "Please confirm all options."
	exit
fi

# go workingDir
if [ "$workingDir" != "" ] ; then
	cd "$workingDir"
fi

# if app is not exist, exit
if [ ! -e "$appName.app" ] ; then
	echo "$appName.app is not founded."
	exit
fi

entitlementsPath="../$appName.entitlements"
if [ ! -e $entitlementsPath ] ; then
	entitlementsPath="../${appName}Release.entitlements"
fi
if [ ! -e $entitlementsPath ] ; then
	entitlementsPath="../${appName}Debug.entitlements"
fi
if [ ! -e $entitlementsPath ] ; then
	echo "Plist $entitlementsPath is not founded."
	echo "Please check sandbox settings."
	exit
fi

# "pkg" overwrite or exit?
if [ -e "pkg" ] ; then
	"Overwrite \"pkg\" directory ? y/N"
	read key
	if [ "$key" = "Y" -o "$key" = "y" ] ;then
		echo "Delete pkg directory."
		rm -rf pkg
	else
		echo "Exit"
		exit
	fi
fi

echo "Start make signed pkg."
mkdir pkg
mkdir pkg/Applications
cp -r $appName.app pkg/Applications/
cd pkg
entitlementsPath="../$entitlementsPath"

codesign --verify \
	--sign "$developerIDApplication" \
	--deep \
	--force \
	--verbose \
	--option runtime \
	--entitlements $entitlementsPath \
	--timestamp Applications/$appName.app

if [ $? -ne 0 ] ; then  
	echo "Error: codesign error."
	exit
fi

pkgutil --check-signature "Applications/$appName.app"

pkgbuild --analyze \
	--root Applications \
	packages.plist

#debug
#less packages.plist

pkgbuild "$appName.pkg" --root Applications --component-plist packages.plist --identifier $identifier --version 1.0.0 --install-location "/Applications"

if [ $? -ne 0 ] ; then  
	echo "Error: pkgbuild error."
	exit
fi

productbuild --synthesize --package "$appName.pkg" Distribution.xml

if [ $? -ne 0 ] ; then  
	echo "Error: productbuild --synthesize error."
	exit
fi

#insert title
sed -e "s/\<pkg-ref/\<title\>$installerTitle\<\/title\>\n    \<allowed-os-versions\>\n        \<os-version min=\"10.15\"\/\>\n    \<\/allowed-os-versions\>\n    \<pkg-ref/" Distribution.xml >> tmp

#debug
#less tmp
#less Distribution.xml

mv tmp Distribution.xml

productbuild --distribution Distribution.xml \
	--package-path "$appName.pkg" \
	"$appName-Distribution.pkg"

if [ $? -ne 0 ] ; then  
	echo "Error: productbuild --distribution error."
	exit
fi

signedPackage="$appName-Distribution_SIGNED.pkg"
productsign --sign "$developerIDInstaller" \
	"$appName-Distribution.pkg" \
	"$signedPackage"

if [ $? -ne 0 ] ; then  
	echo "Error: productsign error."
	exit
fi

pkgutil --check-signature "$signedPackage"

xcrun altool --notarize-app \
	--file "$signedPackage" \
	--primary-bundle-id  $identifier \
	--username $appleId \
	--password $appPass
	
if [ $? -ne 0 ] ; then  
	echo "Error: xcrun error."
	exit
fi