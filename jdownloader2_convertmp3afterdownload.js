// from
// https://board.jdownloader.org/showthread.php?t=70525

/*
    Convert audio files to mp3 format
    Trigger : A download stopped
*/

if (link.finished) {
    var input = link.downloadPath;
    var output = input.replace(/(aac|m4a|ogg|opus)$/, "mp3");

    if (input != output) {
        try {
            var ffmpeg = callAPI("config", "get", "org.jdownloader.controlling.ffmpeg.FFmpegSetup", null, "binarypath");
            var bitrate = callSync(ffmpeg, "-i", input).match(/bitrate: (\d+) kb/)[1];

            callAsync(function(error) {
                !error && getPath(input).delete();
            }, ffmpeg, "-y", "-i", input, "-b:a", bitrate + "k", output);
        } catch (e) {};
    }
}
