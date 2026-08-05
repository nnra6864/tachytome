return {
    -- Set to "" to output clips to the same directory as the original video
    output_dir = "", 
    space_replacement = "_",
    container = "mkv",
    suffix = " Remuxed",
    
    crf = 30,
    preset = 4,
    combine_audio = false,
    trash_original = true,
    
    show_stats_screen = true,
    stats_osd_time = 8
}
