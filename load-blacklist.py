#!/usr/bin/env python3

import os
import sqlite3
import glob
import json
from more_itertools import ichunked

base_dir="/ZFS/ZFS-primary/backups/tiktok-backups"
base_dir="."
video_dir="raw-videos"
database_path=f"{base_dir}/{video_dir}/index.db"

with open("./temp_blacklist", "r") as f:
    video_ids = f.readlines()
    for batch in ichunked(video_ids,500):
        with sqlite3.connect(database_path,timeout = 500) as con:
            for video_id in batch:
                vid_filtered=video_id.strip()
                con.execute("insert into blacklisttable(id, error) values (?,?) on conflict do nothing",(vid_filtered,"TEMP_BLACKLIST"))
            con.commit()
