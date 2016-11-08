# Copyright (c) 2015-2016, Blockbridge Networks LLC.  All rights reserved.
# Use of this source code is governed by a BSD-style license, found
# in the LICENSE file.

module Helpers
  module Refs
    def vol_ref_path(name = nil)
      File.join(vol_path(name), 'ref')
    end

    def mnt_ref_file(name = nil)
      File.join(vol_ref_path(name), 'mnt')
    end

    def get_ref(ref_file)
      begin
        File.open(ref_file, 'r') do |f|
          dat = f.read
          JSON.parse(dat)
        end
      rescue
        FileUtils.mkdir_p(File.dirname(ref_file))
        File.open(ref_file, 'w+') do |f|
          dat = { 'ref' => 0 }
          f.write(dat.to_json)
          f.fsync rescue nil
          dat
        end
      end
    end

    def set_ref(ref_file, dat)
      tmp_file = Dir::Tmpname.make_tmpname(ref_file, nil)
      File.open(tmp_file, 'w') do |f|
        f.write(dat.to_json)
        f.fsync rescue nil
      end
      File.rename(tmp_file, ref_file)
    end

    def ref_incr(file, desc)
      dat = get_ref(file)
      logger.debug "#{vol_name} #{desc} #{dat['ref']} => #{dat['ref'] + 1}"
      dat['ref'] += 1
      set_ref(file, dat)
    end

    def ref_decr(file, desc)
      dat = get_ref(file)
      return if dat['ref'] == 0
      logger.debug "#{vol_name} #{desc} #{dat['ref']} => #{dat['ref'] - 1}"
      dat['ref'] -= 1
      set_ref(file, dat)
    end

    def mount_ref
      ref_incr(mnt_ref_file, "mounts")
    end

    def mount_unref
      ref_decr(mnt_ref_file, "mounts")
    end

    def unref_all
      Dir.foreach(volumes_root) do |vol|
        if vol != '.' && vol != '..'
          FileUtils.rm_rf(File.join(volumes_root, vol, 'ref'))
        end
      end
    end

    def mount_needed?(name = nil)
      dat = get_ref(mnt_ref_file(name))
      return true if dat && dat['ref'] > 0
      false
    end
  end
end
