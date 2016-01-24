#!/bin/bash
#
#  test-raw-formats.sh: Test raw/headerless formats
#
#  This file is a part of vsrawsource
#
#  Copyright (C) 2016  Darrell Walisser
#
#  Authors: Darrell Walisser (my.name at gmail dot com)
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU Lesser General Public
#  License as published by the Free Software Foundation; either
#  version 2.1 of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public
#  License along with Libav; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
#

input="$1"
numFrames=10
numPass=0
numFail=0
requests=1
red="\x1b[31m"
green="\x1b[32m"
reset="\x1b[0m"
    
if [ -z $input ]; then
    echo "usage: $0 file"
    exit -1
fi

# we need the width/height of the input since it can't
# be probed from a raw stream
ffprobe -show_streams "$input" 2>/dev/null > "$input.info"

width=`cat "$input.info" | grep ^width  | sed s/width=//`
height=`cat "$input.info"| grep ^height | sed s/height=//`


# test planar formats
for fmt in \
    yuv410p yuv411p yuv440p \
    yuv420p yuv420p9 yuv420p10 yuv422p16 \
    yuv422p yuv422p9 yuv422p10 yuv422p16 \
    yuv444p yuv444p9 yuv444p10 yuv444p16 \
    
do
    echo -e \\n== Planar $fmt ===============================

    # first pass, checksum the source clip w/o raws
    srcSum=`ffmpeg -loglevel warning -i "$input" -frames $numFrames -pix_fmt $fmt -f rawvideo - | \
            openssl md5`
    
    # second pass, same source clip piped through raws
    echoSum=`ffmpeg -loglevel warning  -i "$input" -frames $numFrames -pix_fmt $fmt -f rawvideo - | \
            vspipe --requests $requests --end $(($numFrames-1)) --arg fmt_=$width:$height:$fmt echo-raw.vpy - | \
            openssl md5`
    
    if [ "$srcSum" = "$echoSum" ]; then
        echo -e ${green}PASS${reset}
        numPass=$(($numPass+1))
    else
        echo -e ${red}FAIL${reset}
        numFail=$(($numFail+1))
    fi
done

# test packed formats
# separate, since vspipe doesn't output packed formats,
# need to verify against the related planar format
for fmt in \
    nv12,yuv420p nv21,yuv420p \
    yuyv422,yuv422p yvyu422,yuv422p uyvy422,yuv422p \
    bgr24,gbrp rgb24,gbrp bgra,gbrp rgba,gbrp \
    
do
    (
        IFS=',';
        set -- $fmt; 
        
        packedFmt=$1
        planarFmt=$2
        
        echo -e \\n== Packed $packedFmt =\> $planarFmt ===============================
        
        # first pass, checksum the source clip w/o raws
        srcSum=`ffmpeg -loglevel warning -i "$input" -frames $numFrames -pix_fmt $packedFmt -f rawvideo - | \
                ffmpeg -loglevel warning -f rawvideo -pixel_format $packedFmt -video_size ${width}x${height} \
                    -i - -frames $numFrames -pix_fmt $planarFmt -f rawvideo - | 
                openssl md5`
        
        # second pass, same source clip piped through raws
        echoSum=`ffmpeg -loglevel warning  -i "$input" -frames $numFrames -pix_fmt $packedFmt -f rawvideo - | \
                vspipe --requests $requests --end $(($numFrames-1)) --arg fmt_=$width:$height:$packedFmt echo-raw.vpy - | \
                openssl md5`
        
        
        if [ "$srcSum" = "$echoSum" ]; then
            echo -e ${green}PASS${reset}
            numPass=$(($numPass+1))
        else
            echo -e ${red}FAIL${reset}
            numFail=$(($numFail+1))
        fi
    )
done


# test rgb formats w/bmp pipe
# todo: test alpha channel in bgra
for fmt in \
    bgr24,gbrp bgra,gbrp
do
    (
        IFS=',';
        set -- $fmt;

        packedFmt=$1
        planarFmt=$2

        echo -e \\n== BMP $packedFmt =\> $planarFmt ===============================

        # first pass, checksum the source clip w/o raws
        srcSum=`ffmpeg -loglevel warning -i "$input" -frames $numFrames -pix_fmt $packedFmt -c:v bmp -f rawvideo - | \
                ffmpeg -loglevel warning -i - -frames $numFrames -pix_fmt $planarFmt -f rawvideo - | 
                openssl md5`

        # second pass, same source clip piped through raws
        echoSum=`ffmpeg -loglevel warning -i "$input" -frames $numFrames -pix_fmt $packedFmt -c:v bmp -f rawvideo - | \
                vspipe --requests $requests --end $(($numFrames-1)) echo-bmp.vpy - | \
                openssl md5`

        if [ "$srcSum" = "$echoSum" ]; then
            echo -e ${green}PASS${reset}
            numPass=$(($numPass+1))
        else
            echo -e ${red}FAIL${reset}
            numFail=$(($numFail+1))
        fi
    )
done

# test rgb formats that need rgb input (no sws yuv->rgb conversion exists)
for fmt in \
    bgr24,gbrp, bgra,gbrp abgr,gbrp argb,gbrp \
    gbrp,gbrp \

do
    (
        IFS=',';
        set -- $fmt;

        packedFmt=$1
        planarFmt=$2

        echo -e \\n== RGB =\> $packedFmt =\> $planarFmt ===============================

        # first pass, checksum the source clip w/o raws
        srcSum=`ffmpeg -loglevel warning -i "$input" -frames $numFrames -pix_fmt bgr24 -c:v bmp -f rawvideo - | \
                ffmpeg -loglevel warning -i - -frames $numFrames -pix_fmt $packedFmt -f rawvideo - | \
                ffmpeg -loglevel warning -f rawvideo -pixel_format $packedFmt -video_size ${width}x${height} \
                    -i - -frames $numFrames -pix_fmt $planarFmt -f rawvideo - |
                openssl md5`

        # second pass, same source clip piped through raws
        echoSum=`ffmpeg -loglevel warning -i "$input" -frames $numFrames -pix_fmt bgr24 -c:v bmp -f rawvideo - | \
                ffmpeg -loglevel warning -i - -frames $numFrames -pix_fmt $packedFmt -f rawvideo - | \
                vspipe --requests $requests --end $(($numFrames-1)) --arg fmt_=$width:$height:$packedFmt echo-raw.vpy - | \
                openssl md5`

        if [ "$srcSum" = "$echoSum" ]; then
            echo -e ${green}PASS${reset}
            numPass=$(($numPass+1))
        else
            echo -e ${red}FAIL${reset}
            numFail=$(($numFail+1))
        fi
    )
done


# todo: untested
# rgb48 rgbp gbrp16
#
