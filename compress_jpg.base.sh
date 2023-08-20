#!/usr/bin/bash
# Parameters for convert
READ_PARAMETERS='-auto-orient -colorspace RGB'
WRITE_PARAMETERS='-quality 85% -colorspace sRGB -interlace Plane -define jpeg:dct-method=float -sampling-factor 4:2:0'

# Return values
BAD_USAGE=1
CONVERT_ERR=2
NO_EXIST=3

# Formatted usage messages
SHORT_USAGE="\e[1mUSAGE\e[0m
    \e[1m${0}\e[0m [\e[1m-c\e[0m] [\e[1m-r\e[0m] [\e[1m-e\e[0m \e[4mextension\e[0m] \e[4mresolution\e[0m [\e[4mfilename_or_directory\e[0m]
or
    \e[1m${0} --help\e[0m
for detailed help."
USAGE="$SHORT_USAGE

The order of the options does not matter. However, if \e[4mfilename_or_directory\e[0m is given and is a number, it must appear after \e[4mresolution\e[0m.

  \e[1m-c\e[0m, \e[1m--strip\e[0m
    Compress more by removing metadata from the file.

  \e[1m-r\e[0m, \e[1m--recursive\e[0m
    If \e[4mfilename_or_directory\e[0m is a directory, recursively compress JPEG in subdirectories.
    Has no effect if \e[4mfilename_or_directory\e[0m is a regular file.
    This option has the same effect when file and directories are given on stdin.

  \e[1m-e\e[0m \e[4mextension\e[0m, \e[1m--ext\e[0m \e[4mextension\e[0m
    Change the extension of processed files to \e[4mextension\e[0m, even if the compression fails or does not actually happen.
    Renaming does not take place if it gives a filename that already exists, nor if the file being processed is not a JPEG file.

  \e[4mresolution\e[0m
    A number indicating the size in pixels of the smallest side.
    Smaller images will not be enlarged, but they will still be potentially compressed.

  \e[4mfilename_or_directory\e[0m
    If a filename is given, the file is compressed. If a directory is given, all the JPEG files in it are compressed.
    Can't begins with a dash (-).
    If it is not given at all, ${0} process files and directories whose name are given on stdin, one by line.

\e[1mDESCRIPTION\e[0m
    Compress the given picture or the jpeg located in the given directory. If none is given, read filenames from stdin, one by line.

\e[1mCOMPRESSION\e[0m
    The file written is a JPEG with quality of 85% and chroma halved. This is a lossy compression to reduce file size. However, it is calculated with precision (so it is not suitable for creating thumbnail collections of large images). The steps of the compression are:

      1. The entire file is read in.
      2. Its color space is converted to a linear space (RGB). This avoids a color shift usually seen when resizing images.
      3. If the smallest side of the image is larger than the given resolution (in pixels), the image is resized so that this side has this size.
      4. The image is converted (back) to the standard sRGB color space.
      5. The image is converted to the frequency domain according to the JPEG algorithm using an accurate Discrete Cosine Transform (DCT is calculated with the float method) and encoded in JPEG 85% quality, chroma halved. (The JPEG produced is progressive: the loading is done on the whole image by improving the quality gradually)."



function print_without_formatting () {
    # Output the value of "$1" without formatting
    echo "$1" | sed 's/\\e\[[0-9;]\+m//g'
}

function parse_args () {
  check_for_help="$@"
  additional_write_parameters=''
  input=''
  extension=''
  recursive=false
  resolution=''
  args=''
  while [ $# -gt 0 ]; do
    case "${1}" in
      -h|--help|help)
        echo -e "$SHORT_USAGE"
        exit $BAD_USAGE
        ;;
      -c|--strip)
        key=-strip
        additional_write_parameters=${key}
        shift
        ;;

      -r|--recursive)
        if [ ! -d ${input} ]; then
          echo "$1 Not necessary, not a directory"  2> /dev/stderr
        fi
        recursive=true
        shift
        ;;
      
      -e|--ext)
        if [[ ${2} != @(jpg|jpeg|jpe||jif|jfif|jfi|JPG|JPEG|JPE|JIF|JFIF|JFI) ]]; then
          echo "-e argument must be one of jpg, jpeg, jpe, jif, jfif, jfi (or uppercase versio,→ of one)" 2> /dev/stderr
          exit $BAD_USAGE
        fi
        extension=${2}
        shift; shift
        ;;

      -*)
        echo "./compress_jpg.base.sh [-c] [-r] [-e extension] resolution [filename_or_directory]" 2> /dev/stderr
        shift
        exit $BAD_USAGE
        ;;

      ''|*[!0-9]*)
        input=${1}
        shift
        ;;
      *)
        if [ -z ${resolution} ]; then
          resolution=${1}
          shift
        else
          input=${1}
          shift
        fi
        ;;
    esac
  done
}

function is_jpeg() {
  local ext="image"
  if [ -f "$1" ]; then
    local var=$(file -i -b $1)
    var=${var%"; charset=binary"}
    if [ "${var%/*}" = ${ext} ]; then
      echo $1
    else
      $(echo $1 neither file and directory exit 3)
    fi
  fi
}

function recurs() {
  if [ -d $1 ]; then
    local dir=$1
    for file in $dir/*; do
      if [ ! -e "$file" ]; then
        $(echo "$dir" is empty, exit $NO_EXIST)
      fi
      name_without_directory=$(basename $file)
      if [ -d "$name_without_directory" ] && $recursive != "false"; then
        recurs ${name_without_directory}
      elif [ -f "$file" ]; then
        cd ${file%/*}
        normalize $name_without_directory 
      else
        $(echo "$file" is not an image, exit $NO_EXIST)
      fi
    done
  else
    normalize "$1"
  fi
}

function normalize () {
  if [ -n "$extension" ] && is_jpeg "$1" ; then
    if [ -z "${1#*.}" ]; then
      if [ -e "${1}.$extension" ]; then
        input_filename=$1
      else
        input_filename="${1}.${extension}"
      fi
      output_filename=$(mktemp "${1%.*}XXX.$extension")
    else
      input_filename="$1"
      output_filename=$(mktemp "${1%.*}XXX.${1#*.}")
    fi
    if [ -n $additional_write_parameters ]; then
      $(convert ${READ_PARAMETERS} ${input_filename} -resize ${resolution}x"${resolution}^>" ${additionnal_write_parameters} ${WRITE_PARAMETERS} ${output_filename})
    else
      $(convert ${READ_PARAMETERS} ${input_filename} -resize ${resolution}x"${resolution}^>" ${WRITE_PARAMETERS} ${output_filename})
    fi

    if [ "$?" != "0" ]; then
        $(echo "l'appel a convert à echouer" exit $CONVERT_ERR)
    fi

    size_input=$(stat --format=%s "$input_filename")
    size_output=$(stat --format=%s "$output_filename")

    if [ $size_input ] && [ $size_output ] && [ $size_output -lt $size_input ]; then
      cp ${output_filename} ${input_filename}
      rm $output_filename
      echo $input_filename
      exit 0
    else
      rm $output_filename
      echo "$1, fichier déjà petit" 
    fi
  else
    echo "$1" 
    echo "Not compressed. File left untouched"
  fi
}
 
parse_args "$@"
if [ -z ${input} ] && [ -n $resolution ]; then
  echo "Type your Files/Directory"
  while read input; do
    recurs "${input}"
  done
elif [ -z $resolution ]; then
  recurs "${input}"
else
  echo "Missing resolution"
  exit $BAD_USAGE
fi
