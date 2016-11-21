#!/bin/bash

TMP_FOLDER="/tmp/find-artifacts"
MODULES_GROUP_ID="com.liferay"
MAVEN_REPO_MODULES_URL="https://repository.liferay.com/nexus/content/repositories/liferay-public-releases/com/liferay"
MAVEN_NAMESPACE="http://maven.apache.org/POM/4.0.0"

# Finds all the artifacts contained in the OSGi modules
# Parameters:
# 1. The path to Liferay's OSGi package zip
# 2. The name of the folder inside the OSGi package zip
# 3. The temporary folder where stuff will be extracted. By default, '/tmp/find-artifacts'
doFindArtifacts() {
    OSGI_ARCHIVE="${1}"
    OSGI_FOLDER="${2}"

    TMP_FOLDER_ESCAPED=${TMP_FOLDER//\//\\/}
    MAVEN_REPO_MODULES_URL_ESCAPED=${MAVEN_REPO_MODULES_URL//\//\\/}
    MAVEN_REPO_MODULES_URL_ESCAPED=${MAVEN_REPO_MODULES_URL_ESCAPED//:/\\:}

    # Empty TMP directory
    rm -rf ${TMP_FOLDER}/*

    mkdir ${TMP_FOLDER}/extracts
    mkdir ${TMP_FOLDER}/downloads

    # Extract OSGi package
    unzip -q -d ${TMP_FOLDER} ${OSGI_ARCHIVE}

    echo "Extracting LPKGs"
    # Find all LPKGs and extract them
    find ${TMP_FOLDER}/${OSGI_FOLDER}/osgi/marketplace -type 'f' -iname '*.lpkg' -exec unzip -q -o -d ${TMP_FOLDER}/extracts '{}' \;

    echo "Removing non-liferay modues"
    # Remove all non-liferay module files
    find ${TMP_FOLDER}/extracts -type 'f' ! -iname 'com.liferay.*.jar' -exec rm '{}' \;

    # Download Maven metadata
    URL_LIST=$(find ${TMP_FOLDER}/extracts -type 'f' -iname '*.jar' | \
        sed -e "s/${TMP_FOLDER_ESCAPED}\/extracts\///" \
            -e "s/\.jar//" \
            -e "s/\-/\//" \
            -e "s/\(.*\)\/\(.*\)/${MAVEN_REPO_MODULES_URL_ESCAPED}\/\1\/\2\/\1-\2\.pom\\n${MAVEN_REPO_MODULES_URL_ESCAPED}\/\1\/\2\/\1-\2\.pom.sha1/" \
    )

    echo "Downloading all Maven descriptors (this may take a while)"
    # Download all artifacts
    cd ${TMP_FOLDER}/downloads
    while read -r URL; do
        curl -f --tlsv1.2 -s -O ${URL}
        if [[ $? -ne 0 ]] ; then
            echo "Cannot download ${URL}"
        fi
    done <<< "${URL_LIST}"
    cd -

    cd ${TMP_FOLDER}/downloads
    FILE_LIST=$(find -type 'f' -iname '*.pom' | sed -e 's/\.\///')
    echo "<dependencyManagement>" > ../results.pom
    while read -r FILE_NAME; do
        echo -n "  ${FILE_NAME}" >> "${FILE_NAME}.sha1"
        sha1sum --status -c "${FILE_NAME}.sha1"
        if [[ $? -ne 0 ]] ; then
            echo "Checksum mismatch for ${FILE_NAME} - removing it"
            rm "${FILE_NAME}"
            rm "${FILE_NAME}.sha1"
        else
            echo "    <dependency>" >> ../results.pom
            echo -n "        <groupId>" >> ../results.pom
            xmlstarlet sel -N x=${MAVEN_NAMESPACE} -T -t -v '/x:project/x:groupId' ${FILE_NAME} >> ../results.pom
            echo "</groupId>" >> ../results.pom

            echo -n "        <artifactId>" >> ../results.pom
            xmlstarlet sel -N x=${MAVEN_NAMESPACE} -T -t -v '/x:project/x:artifactId' ${FILE_NAME} >> ../results.pom
            echo "</artifactId>" >> ../results.pom

            echo -n "        <version>" >> ../results.pom
            xmlstarlet sel -N x=${MAVEN_NAMESPACE} -T -t -v '/x:project/x:version' ${FILE_NAME} >> ../results.pom
            echo "</version>" >> ../results.pom
            echo "    </dependency>" >> ../results.pom
        fi
    done <<< "${FILE_LIST}"
    echo "</dependencyManagement>" >> ../results.pom
    echo "Results in ${TMP_FOLDER}/results.pom"
    cd -

}

doUsage() {
    echo "find-artifacts.sh osgi-file osgi-folder"
    echo "Where :"
    echo "* 'osgi-file' is the path to Liferay's OSGi package zip"
    echo "* 'osgi-folder' The name of the folder inside the OSGi package zip"
}

if [[ "" == "${1}" || "" == "${2}" ]] ; then
    doUsage
else
    doFindArtifacts ${1} ${2}
fi
