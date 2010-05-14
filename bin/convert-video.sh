#!/usr/bin/env /bin/bash
# Copyright (c) 2010, Max Klymyshyn
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 3. All advertising materials mentioning features or use of this software
#    must display the following acknowledgement:
#    This product includes software developed by the Sonettic.
# 4. Neither the name of the Sonettic nor the
#    names of its contributors may be used to endorse or promote products
#    derived from this software without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY MAX KLYMYSHYN ''AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL MAX KLYMYSHYN BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# 


# definition of binaries and folders
FFMPEG_PATH=/opt/local/bin/ffmpeg
STATUS_DIRECTORY=/tmp/videoconv
TEMPORARY_THUMBNAILS_DIRECTORY=/tmp/videoconv/thumbnails
MAX_QUEUE_COUNT=3


# offset from video begin in percents
THUMBNAIL_OFFSETS="3 10 40 70"
THUMBNAIL_ARGUMENTS="-y -vcodec mjpeg -sameq -vframes 1 -an -f rawvideo"
THUMBNAIL_EXT=".jpg"

# definition of main variables
MP4_CONV_ARGS=<< EOF
        -acodec libfaac -ar 44100 -ab 192k \
        -ac 2 -subq 7 \
        -sc_threshold 40 -vcodec libx264 -b 2000k -vpre hq -crf 22 \
        -cmp +chroma     +parti4x4+partp8x8+partb8x8 \
        -i_qfactor 0.71 -keyint_min 25 \
        -b_strategy 1 -g 250 -r 25
EOF

FLV_CONV_ARGS="-acodec libfaac -ar 22050 -ab 96k -qscale 1"
        
CONV_TYPE=
NICE_CMD="nice -n 13"
PYTHON_CMD="python"


# global variables whith may redefined by options
INPUT_FILE=
OUTPUT_FILE=
QUEUE_UNIQUE_ID=
PROGRESS_PREFIX="queue_"
COMPLETE_PREFIX="complete_"
ERROR_PREFIX="error_"
DELAYED_PREFIX="delayed_"
THUMBS_PREFIX="tb_"
UNREGISTER_QUEUE=
DISPLAY_STATUS=
USE_DELAYED_CONV=
GENERATE_THUMBNAILS_AFTER_CONVERTING=
ADDITIONAL_FFMEPEG_ARGUMENTS=


# display usage message
usage()
{
cat << EOF
usage: $0 options

This script convert video from most popular video formats
to mp4 or flv formats with ffmpeg tool.

OPTIONS:
   -h      Show this message
   -t      Type of conversion - flv or mp4
   -i      Input video file
   -o      Output video file
   -d      Path to status directory
   -a      Path to FFMPEG executable
   -s      Status of conversion. It\'s possible to specify status for 
           conversion id defined by -q option
   -q      Queue unique identifier
   -u      Unregister queue with id specified by -q option
   -g      Generate thumbnails for converted video with ID specified by -q option
   -r      Use delayed conversion (defined in QUEUE_SIZE)
   -c      Generate thumbnails after converting are finished
   -f      Custom options for FFMPEG
   
EOF
}

# parsing arguments
while getopts "uhsrct:i:o:a:d:f:q:g" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         t)
             CONV_TYPE=$OPTARG
             ;;
         i)
             INPUT_FILE=$OPTARG
             ;;
         o)
             OUTPUT_FILE=$OPTARG
             ;;
         a)
             FFMPEG_PATH=$OPTARG
             ;;
         d)
             STATUS_DIRECTORY=$OPTARG
             ;;
         q)
             QUEUE_UNIQUE_ID=$OPTARG
             ;;
         u)  
             UNREGISTER_QUEUE="1"
             ;;
         s)
             DISPLAY_STATUS="1"
             ;;
         g)
             GENERATE_THUMBNAILS="1"
             ;;
         r)
             USE_DELAYED_CONV="1"
             ;;
         c)  
             GENERATE_THUMBNAILS_AFTER_CONVERTING="1"
             ;;
         f)  
             ADDITIONAL_FFMEPEG_ARGUMENTS=$OPTARG
             ;;
         ?)
             usage
             exit
             ;;
     esac
done


# conversation
FFMPEG="$NICE_CMD $FFMPEG_PATH"


# ceil math function
function ceil { echo "[1+]sa $1 $2 ~ 0 !=a p" | dc; }

# get video duration from file
_get_video_duration(){
    # arguments: path_to_file
    echo `cat $1 | awk '/Duration/{print $2}' | sed 's/,//' | awk -F: '{print $1*60*60 + $2 * 60 + $3 }'`
}


# parse video status file and return string with progress of video conversion
_get_current_progress(){
    # arguments: path_to_file
    
$PYTHON_CMD <<EOF
import re

f = open("$1")
data = f.read()
f.close()
pref = "frame="
reversed_file = data.split("\r")
reversed_file.reverse()
for l in reversed_file:
    if l[:len(pref)] == pref:
        # prepare all key/values, remove spaces and add separator $
        print "$".join(map(lambda a: "%s=%s" % (a[0], a[1]), re.findall(r'(\w+)=\s*(\w*)\s*', l)))
        break
EOF
}

# get value from ffmpeg prepared string by key
get_value_by_key(){
    # arguments: string, key
    KEY=$2
    SOURCE=$1
    
    echo $SOURCE | awk -F\$ '{for(i=1;i<NF;i++)print $i;}' | grep "^${KEY}=" | cut -d '=' -f 2
}


# get file name by conversion id
_get_file_by_id(){
    # arguments: video_id
    VIDEO_ID=$1
    for file in `ls -l "${STATUS_DIRECTORY}" | grep ^- | awk '{print $9}'`; do
        filepath=${STATUS_DIRECTORY}/${file}        
        conv_id=`head -n 1 $filepath`
        if [ "$conv_id" == "$VIDEO_ID" ]; then
            echo $filepath
            exit
        fi
    done    
}

# is video currently in progress
_is_in_progress(){
    # arguments: video_id
    VIDEO_ID=$1
    for file in `ls -l "${STATUS_DIRECTORY}" | grep ^- | awk '{print $9}'`; do
        filepath=${STATUS_DIRECTORY}/${file}
        
        conv_id=`head -n 1 $filepath`
        file_prefix=`echo $file | cut -d _ -f 1`
        
        if [ "$conv_id" == "$VIDEO_ID" ]; then
            if [ "${file_prefix}_" == "${PROGRESS_PREFIX}" ]; then
                echo "Progress"
                exit
            fi
        fi
    done    
}


# decide add
delayed_conversion(){
    # arguments: args
    if [ -z "$USE_DELAYED_CONV" ]; then
        exit;
    fi
    
    count=`ls -l "${STATUS_DIRECTORY}" | grep ^- | awk '{print $9}' | grep "^${PROGRESS_PREFIX}" | wc -l`
    if [ $count -gt $MAX_QUEUE_COUNT ]; then
        filename=`conversion_queue ${DELAYED_PREFIX}`
        echo "$@" > $filename
        echo "Delayed"
    fi
}

# next delayed conversion from queue
next_delayed_conversion(){
    # arguments: none
    count=`ls -l "${STATUS_DIRECTORY}" | grep ^- | awk '{print $9}' | grep "^${PROGRESS_PREFIX}" | wc -l`
    if [ $count -gt $MAX_QUEUE_COUNT ]; then
        # skip conversion if queue is full
        exit;
    fi
    
    for file in `ls -l "${STATUS_DIRECTORY}" | grep ^- | awk '{print $9}' | grep "^${DELAYED_PREFIX}"`; do
        
        args=`cat ${STATUS_DIRECTORY}/$file`
        echo "Start delayed conversion with arguments: ${args}"
        # remove this delayed conversion
        rm ${STATUS_DIRECTORY}/$file
        
        # run another one conversion
        $0 $args
        
        exit
    done
}

# Generate thumbnails
generate_thumbnails(){
    # arguments: video_id
    VIDEO_ID=$1
    filepath=`_get_file_by_id $VIDEO_ID`
    
    
    if [ ! -e "$filepath" ]; then
        error "Info file for conversion ID $VIDEO_ID not found."
        exit
    fi

    status=`_is_in_progress $VIDEO_ID`
    if [ -n "$status" ]; then
        error "This video still in process of conversion"
        exit
    fi
    
    # generate desination folder
    DST_FOLDER="${TEMPORARY_THUMBNAILS_DIRECTORY}/${THUMBS_PREFIX}${VIDEO_ID}"
    SOURCE_FILENAME=`cat $filepath | grep 'Output' | awk '{print $NF}' | sed "s/'://g"`    
    SOURCE_FILENAME=`echo $SOURCE_FILENAME | sed "s/'//g"`

    # create empty desination folder
    if [ ! -d "$DST_FOLDER" ]; then
        mkdir $DST_FOLDER
        if [ ! -d "$DST_FOLDER" ]; then
            error "Can't create new directory $DST_FOLDER"
            exit
        fi        
    fi

	# get file length
	LENGTH=`_get_video_duration $filepath`    
	PREVIEW_PREFIX='cover'
    
	# check video length. If it's zero - stop execution
	if [ `$PYTHON_CMD -c "print int(round(${LENGTH}))"` -eq 0 ]; then
		error "Length of the video is zero"
		exit 1
	fi
	
	
	# convert shifts from percents to seconds
	SHIFTS=`$PYTHON_CMD -c "print ' '.join([str(int(float(p)/100.0 * ${LENGTH})) for p in '${THUMBNAIL_OFFSETS}'.split(' ')])"`
	
	
	# make thumbnails
	NUM=1
	for shot in $SHIFTS; do
		FILENAME="${DST_FOLDER}/${PREVIEW_PREFIX}${NUM}${THUMBNAIL_EXT}"
		${FFMPEG} -itsoffset -${shot} -i $SOURCE_FILENAME $THUMBNAIL_ARGUMENTS $FILENAME > /dev/null 2>&1
		NUM=`expr ${NUM} + 1`
		echo "${FILENAME}"		
	done;
}

# unregister specified queue
unregister_queue(){
    # arguments: unique_id 
    for file in `ls -l "${STATUS_DIRECTORY}" | grep ^- | awk '{print $9}'`; do
        filepath=${STATUS_DIRECTORY}/${file}
        conv_id=`head -n 1 $filepath`
        file_prefix=`echo $file | cut -d _ -f 1`
        
        if [ "$conv_id" == "${1}" ]; then
            # skip unregister if conversation in progress
            if [ "${file_prefix}_" == "${PROGRESS_PREFIX}" ]; then
                error "Conversion with id $1 still in progress. You can't unregister it."
                exit
            fi
                        
            # remove thumbnails and thumbnails folder if available
            DST_FOLDER="${TEMPORARY_THUMBNAILS_DIRECTORY}/${THUMBS_PREFIX}${conv_id}"
            if [ -d "$DST_FOLDER" ]; then
                for thumb in `ls "$DST_FOLDER"`; do
                    rm ${DST_FOLDER}/${thumb}
                done
                rmdir $DST_FOLDER
            fi
            
            
            # remove file with status
            rm $filepath
            echo "Conversation with id [$1] unregistered successfully."
            exit;
        fi
    done
    warn "This conversation already unregistered"
}

# recognize errors
have_errors(){
    # arguments: filename
    no_file=`cat $1 | grep "no such file or directory"`
    unknown_format=`cat $1 | grep "Unknown format"`
    
    # change filename to error prefix
    handle_error(){
        # arguments: filename
        error_filename=`conversion_queue "${ERROR_PREFIX}"`
        mv $1 $error_filename        
        echo $error_filename
    }
    
    if [ -n "$no_file" ]; then
        # rename original file to error
        handle_error $1;
    elif [ -n "$unknown_format" ]; then
        handle_error $1;
    fi
}

# display status of conversation
show_status(){
    # arguments: unique_id(optional)
    thumbs_dir=`basename $TEMPORARY_THUMBNAILS_DIRECTORY`
    # display status
    # Parse queue files and calculate conversion
    echo "ID    File    Input    Duration(sec)    Progress(sec)    Progress(size)    Progress(%)    Status"
    for file in `ls -l "${STATUS_DIRECTORY}" | grep ^- | awk '{print $9}'`; do
        filepath=${STATUS_DIRECTORY}/${file}

        file_prefix=`echo $file | cut -d _ -f 1`
        conv_id=`head -n 1 $filepath`

        conv_status="Unknown"
        if [ "${file_prefix}_" == "${COMPLETE_PREFIX}" ]; then
            conv_status="Complete"
        elif [ "${file_prefix}_" == "${PROGRESS_PREFIX}" ]; then
            conv_status="Processing"
        elif [ "${file_prefix}_" == "${ERROR_PREFIX}" ]; then
            conv_status="Error"            
        elif [ "${file_prefix}_" == "${DELAYED_PREFIX}" ]; then
            conv_status="Delayed"
            conv_id="D"
        fi                        

        # specify status for concrete file
        if [ -n "$1" ]; then
            if [ "$conv_id" != "$1" ]; then                
                continue
            fi            
        fi
        
        # display status of conversion with details
        if [ "$conv_status" != "Error" -a "$conv_status" != "Delayed" ]; then            
            duration=`_get_video_duration $filepath`
            status=`_get_current_progress $filepath`
            already_converted=`get_value_by_key $status 'time'`            
            converted_filesize=`get_value_by_key $status 'Lsize'`
            [[ -z "$converted_filesize" ]] && converted_filesize=`get_value_by_key $status 'size'`
                                
            
            source_filename=`cat $filepath | grep 'Input' | awk '{print $NF}' | sed "s/'://g"`
            source_filename=`basename $source_filename`
            
            progress_in_percents=$(ceil `echo "scale=4; ($already_converted / $duration * 100)" | bc` 1)
        else
            duration="1"
            already_converted="0"
            converted_filesize="0"
            source_filename="Unknown"            
            progress_in_percents=0
        fi
        # display information about this file
        printf "%s    %s    %s...    %s    %s    %s    %s    %s\n" \
                $conv_id $file ${source_filename:0:5} $duration $already_converted \
                $converted_filesize \
                $progress_in_percents \
                $conv_status        
    done
    
}

# get count of current conversion
conversion_queue(){
    # arguments: file_prefix
    cur_count=`ls "${STATUS_DIRECTORY}" | grep -c "^${1}"`
    count=$(($cur_count+1))
    new_filename="${STATUS_DIRECTORY}/${1}${count}"
    
    # generate new queue filename    
    if [ -e "$new_filename" ]; then
        count=0
        until [ ! -e "$new_filename" ]; do
            count=$(($count+1))
            new_filename="${STATUS_DIRECTORY}/${1}${count}"
        done
    fi
    
    touch $new_filename
    echo $new_filename
}



# display error
error(){ 
    # arguments: error_message
    echo "ERROR: $1"; 
}

# display warning
warn(){ 
    # arguments: warning_message
    echo "WARNING: $1"; 
}


# create directory if not exist
if [ ! -d "$STATUS_DIRECTORY" ]; then 
    mkdir $STATUS_DIRECTORY
fi

if [ ! -d "$TEMPORARY_THUMBNAILS_DIRECTORY" ]; then
    mkdir $TEMPORARY_THUMBNAILS_DIRECTORY
fi

# show status
if [ -n "$DISPLAY_STATUS" ]; then
    show_status $QUEUE_UNIQUE_ID | column -xt    
    exit
fi

# generate thumbnails for video
if [ -n "$GENERATE_THUMBNAILS" ]; then
    if [ -z "$QUEUE_UNIQUE_ID" ]; then
        error "Please specify unique queue ID to generate thumbnails for it"
        exit;
    fi
    generate_thumbnails $QUEUE_UNIQUE_ID 
    exit
fi

# unregister queue
if [ -n "$UNREGISTER_QUEUE" ]; then
    if [ -z "$QUEUE_UNIQUE_ID" ]; then
        error "Please specify unique queue ID to unregister"
        exit;
    fi
    unregister_queue $QUEUE_UNIQUE_ID
    exit
fi

# if no input or output names defined
if [ -z "$QUEUE_UNIQUE_ID" ]; then
    warn "This conversion doesn't have unique Identifier. Please, specify to work with external unitilities"
fi

# if no input or output file specified generate error message
if [ -z "$INPUT_FILE" -o -z "$OUTPUT_FILE" ]; then
    error "No input or output files defined"
    usage
    exit
fi


# if using delayed conversion - add it to queue and exit
if [ -n "$USE_DELAYED_CONV" ]; then    
    delayed=`delayed_conversion "$@"`
    if [ -n "$delayed" ]; then
        echo "This conversion have been delayed..."
        exit
    fi        
fi

# generate queue filename
queue_filename=`conversion_queue "${PROGRESS_PREFIX}"`
echo "${QUEUE_UNIQUE_ID}" > $queue_filename

# convert to mp4
if [ "${CONV_TYPE}" == "mp4" ]; then
    ${FFMPEG} -y -i "${INPUT_FILE}" $MP4_CONV_ARGS "${OUTPUT_FILE}" >> ${queue_filename} 2>&1
fi
# convert to flv
if [ "${CONV_TYPE}" == "flv" ]; then        
    ${FFMPEG} -y -i "${INPUT_FILE}" $FLV_CONV_ARGS "${OUTPUT_FILE}" >> ${queue_filename} 2>&1
fi

# convert with custom arguments
if [ -n "${ADDITIONAL_FFMEPEG_ARGUMENTS}" ]; then
    ${FFMPEG} -y -i "${INPUT_FILE}" $ADDITIONAL_FFMEPEG_ARGUMENTS "${OUTPUT_FILE}" >> ${queue_filename} 2>&1
fi


# check for errors
errors=`have_errors ${queue_filename}`

# if no errors available mark as complete
# in other case - display message about error
if [ -n "$errors" ]; then
    error "Something went wrong. Please review details in:$errors"
else  
    # move queue filename to complete filename
    complete_filename=`conversion_queue "${COMPLETE_PREFIX}"`
    mv $queue_filename $complete_filename
    
    # automatically generate thumbnails for converted video
    if [ -n "$QUEUE_UNIQUE_ID" -a -n "${GENERATE_THUMBNAILS_AFTER_CONVERTING}" ]; then
        $0 -g -q $QUEUE_UNIQUE_ID
    fi
fi

# run next delayed conversion if it exists
if [ -n "$USE_DELAYED_CONV" ]; then
    next_delayed_conversion
fi
