{
  description = "Regular snapshots of various conda channels";

  inputs = rec {
    nixpkgs.url = "nixpkgs/nixos-unstable";
  };

  outputs = inp:
    with builtins;
    with inp.nixpkgs.lib;
    let
      systems = ["x86_64-linux"];
      self = {
        lib.formatVersion = toInt (readFile ./FORMAT_VERSION);
      } 
      // foldl' (a: b: recursiveUpdate a b) {} ( map ( system:
        let
          pkgs = inp.nixpkgs.legacyPackages."${system}";
        in {

          # apps to update the database
          # All apps assume that the current directory is a git checkout of this project
          apps."${system}" = rec {

            # pull latest conda channels into the current git tree
            update-conda.type = "app";
            update-conda.program = toString (pkgs.writeScript "update-conda" ''
              #!/usr/bin/env bash
              set -e
              export PATH=${makeBinPath (with pkgs; [ busybox curl git jq moreutils openssl python3 ])}

              echo $(date +%s) > UNIX_TIMESTAMP

              # main repos
              for channel in main free r; do
                [ ! -e $channel ] && mkdir $channel
                for arch in linux-64 linux-aarch64 noarch osx-64; do
                  url=https://repo.anaconda.com/pkgs/$channel/$arch/repodata.json
                  echo "processing $url"
                  curl -H "Accept-Encoding: gzip" -L $url > .tmpfile
                  cat .tmpfile | gzip -d | sponge .tmpfile
                  if [ "$(cat .tmpfile)" == "" ]; then
                    rm -f $channel/$arch.json
                  else
                    mv .tmpfile $channel/$arch.json
                    python3 ${./split-json.py} $channel/$arch.json
                  fi
                done
              done

              # user repos
              for channel in conda-forge intel; do
                [ ! -e $channel ] && mkdir $channel
                for arch in linux-64 linux-aarch64 noarch osx-64; do
                  url=https://conda.anaconda.org/$channel/$arch/repodata.json
                  echo "processing $url"
                  curl -H "Accept-Encoding: gzip" -L $url > .tmpfile
                  cat .tmpfile | gzip -d | sponge .tmpfile
                  if [ "$(cat .tmpfile)" == "" ]; then
                    rm -f $channel/$arch.json
                  else
                    mv .tmpfile $channel/$arch.json
                    python3 ${./split-json.py} $channel/$arch.json
                  fi
                done
              done

              # generate checksums over files
              echo "{}" > sha256.json
              for f in $(find . -type f -not -path './.git/*' -not -name '.*' -not -name 'sha256*'); do
                jq  ". + {\"$f\": \"$(cat $f | openssl dgst -binary -sha256 | openssl base64 | awk '{print $1}')\"}" sha256.json \
                  | sponge sha256.json
              done
            '');

            # job including git commit for executing in CI system
            job-conda.type = "app";
            job-conda.program = toString (pkgs.writeScript "job-conda" ''
              #!/usr/bin/env bash
              set -e
              set -x

              ${update-conda.program}

              # commit to git
              git add .
              git pull origin $(git rev-parse --abbrev-ref HEAD)
              git commit -m "$(date) - update"
            '');
          };

        }) systems);
    in
      self;
}