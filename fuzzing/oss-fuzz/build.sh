#!/bin/bash -eu
# Copyright 2019 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
################################################################################

# add the flags to Qt build, gratefully borrowed from karchive
cd $SRC/qt/qtbase/mkspecs
sed -i -e "s/QMAKE_CXXFLAGS    += -stdlib=libc++/QMAKE_CXXFLAGS    += -stdlib=libc++  $CXXFLAGS\nQMAKE_CFLAGS += $CFLAGS/g" linux-clang-libc++/qmake.conf
sed -i -e "s/QMAKE_LFLAGS      += -stdlib=libc++/QMAKE_LFLAGS      += -stdlib=libc++ -lpthread $CXXFLAGS/g" linux-clang-libc++/qmake.conf

# set optimization to O1
sed -i -e "s/QMAKE_CFLAGS_OPTIMIZE      = -O2/QMAKE_CFLAGS_OPTIMIZE      = -O1/g" common/gcc-base.conf
sed -i -e "s/QMAKE_CFLAGS_OPTIMIZE_FULL = -O3/QMAKE_CFLAGS_OPTIMIZE_FULL = -O1/g" common/gcc-base.conf

# remove -fno-rtti which conflicts with -fsanitize=vptr when building with sanitizer undefined
sed -i -e "s/QMAKE_CXXFLAGS_RTTI_OFF    = -fno-rtti/QMAKE_CXXFLAGS_RTTI_OFF    = /g" common/gcc-base.conf

# build project
cd $WORK
MAKEFLAGS=-j$(nproc) $SRC/qt/configure -qt-libmd4c -platform linux-clang-libc++ -static -opensource -confirm-license -no-opengl -nomake tests -nomake examples -prefix $PWD/qtbase -D QT_NO_DEPRECATED_WARNINGS
make -j$(nproc) > /dev/null

# prepare corpus files
zip -j $WORK/cbor $SRC/qtqa/fuzzing/testcases/cbor/*
zip -j $WORK/html $SRC/qtqa/fuzzing/testcases/html/*
zip -j $WORK/images $SRC/qtqa/fuzzing/testcases/{bmp,gif,jpg,svg,xbm,xpm}/* $SRC/afltestcases/images/*/*
zip -j $WORK/markdown $SRC/qtqa/fuzzing/testcases/markdown/*
zip -j $WORK/ssl.pem.zip $SRC/qtqa/fuzzing/testcases/ssl.pem/*
zip -j $WORK/svg $SRC/qtqa/fuzzing/testcases/svg/*
zip -j $WORK/text $SRC/qtqa/fuzzing/testcases/text/* $SRC/afltestcases/others/text/*
zip -j $WORK/xml $SRC/qtqa/fuzzing/testcases/xml/* $SRC/afltestcases/others/xml/*

# build fuzzers

build_fuzzer() {
    local module=$1
    local proFilePath=$2
    local format=${3-""}
    local dictionary=${4-""}
    local proFileName=${proFilePath##*/}
    local exeName=${proFileName%%.*}
    local proFileDir=${proFilePath%/*}
    local targetName="$module"_${proFileDir//\//_}
    mkdir build_fuzzer
    cd build_fuzzer
    $WORK/qtbase/bin/qmake $SRC/qt/$module/tests/libfuzzer/$proFilePath
    make -j$(nproc)

    mv $exeName $OUT/$targetName
    if [ -n "$format" ]; then
        cp $WORK/$format.zip $OUT/"$targetName"_seed_corpus.zip
    fi
    if [ -n "$dictionary" ]; then
        cp $dictionary $OUT/$targetName.dict
    fi
    cd ..
    rm -r build_fuzzer
}

build_fuzzer "qtbase" "corelib/serialization/qcborstreamreader/next/next.pro" "cbor"
build_fuzzer "qtbase" "corelib/serialization/qcborvalue/fromcbor/fromcbor.pro" "cbor"
build_fuzzer "qtbase" "corelib/serialization/qtextstream/extractionoperator-float/extractionoperator-float.pro" "text"
build_fuzzer "qtbase" "corelib/serialization/qxmlstream/qxmlstreamreader/readnext/readnext.pro" "xml" "$SRC/afldictionaries/xml.dict"
build_fuzzer "qtbase" "corelib/text/qregularexpression/optimize/optimize.pro" "" "$SRC/afldictionaries/regexp.dict"
build_fuzzer "qtbase" "corelib/tools/qcryptographichash/result/result.pro"
build_fuzzer "qtbase" "gui/image/qimage/loadfromdata/loadfromdata.pro" "images"
build_fuzzer "qtbase" "gui/painting/qcolorspace/fromiccprofile/fromiccprofile.pro" "" "$SRC/afldictionaries/iccprofile.dict"
build_fuzzer "qtbase" "gui/text/qtextdocument/sethtml/sethtml.pro" "html" "$SRC/afldictionaries/html_tags.dict"
build_fuzzer "qtbase" "gui/text/qtextdocument/setmarkdown/setmarkdown.pro" "markdown" "$SRC/afldictionaries/markdown.dict"
build_fuzzer "qtbase" "gui/text/qtextlayout/beginlayout/beginlayout.pro" "text"
build_fuzzer "qtbase" "network/ssl/qsslcertificate/qsslcertificate/pem/pem.pro" "ssl.pem"
build_fuzzer "qtsvg" "svg/qsvgrenderer/render/render.pro" "svg" "$SRC/afldictionaries/svg.dict"
