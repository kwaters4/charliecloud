load ../common
tag=bucache

# WARNING: Git timestamp precision is only one second [1]. This can cause
# unstable sorting within --tree output because the tests commit very fast. If
# it matters, add a “sleep 1”.
#
# [1]: https://stackoverflow.com/questions/28237043


treeonly () {
    # Remove (1) everything including and after first blank line and (2)
    # trailing whitespace on each line.
    sed -E -e '/^$/Q' -e 's/\s+$//'
}

setup () {
    scope standard
    [[ $CH_BUILDER = ch-image ]] || skip 'ch-image only'
    # Use a separate storage directory so we don't mess up the main one.
    export CH_IMAGE_STORAGE=$BATS_TMPDIR/butest
    dot_base=$BATS_TMPDIR/bu_
    if [[ -z $git_version ]]; then
        pedantic_fail "git not in path"
    fi
    if [[ $(  printf '%s\n%s\n' "2.28.1" "$git_version" \
            | sort -V | head -n1) != "2.28.1" ]]; then
        pedantic_fail "git version '$git_version' < 2.28.1"
    fi
}

@test "${tag}/§3.1 empty cache" {
    rm -Rf --one-file-system "$CH_IMAGE_STORAGE"

    blessed_tree=$(cat << EOF
initializing storage directory: v3 ${CH_IMAGE_STORAGE}
initializing empty build cache
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}empty"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}

@test "${tag}/reset" {
    # re-init
    run ch-image build-cache --reset
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'deleting build cache'* ]]
    [[ $output = *'initializing empty build cache'* ]]

    # fail if build cache disabled
    run ch-image build-cache --bucache=disabled --reset
    [[ $status -eq 1 ]]
    echo "$output"
    [[ $output = *'build-cache subcommand invalid with build cache disabled'* ]]
}

@test "${tag}/§3.2.1 initial pull" {
    ch-image pull alpine:3.9

    blessed_tree=$(cat << 'EOF'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}initial-pull"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}

@test "${tag}/§3.5 FROM" {
    # FROM pulls
    ch-image build-cache --reset
    run ch-image build -v -t d -f bucache/from.df .
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1. FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (d, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}from"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)

    # FROM doesn't pull (same target name)
    run ch-image build -v -t d -f bucache/from.df .
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (d, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)

    # FROM doesn't pull (different target name)
    run ch-image build -v -t d2 -f bucache/from.df .
    echo "$output"
    [[ $status -eq 0 ]]
    [[ $output = *'1* FROM alpine:3.9'* ]]
    blessed_tree=$(cat << 'EOF'
*  (d2, d, alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_tree") <(echo "$output" | treeonly)
}

@test "${tag}/§3.3.1 Dockerfile A" {
    ch-image build-cache --reset

    ch-image build -t a -f bucache/a.df .

    blessed_out=$(cat << 'EOF'
*  (a) RUN echo bar
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}a"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.3.2 Dockerfile B" {
    ch-image build-cache --reset

    ch-image build -t a -f bucache/a.df .
    ch-image build -t b -f bucache/b.df .

    blessed_out=$(cat << 'EOF'
*  (b) RUN echo baz
*  (a) RUN echo bar
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}b"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.3.3 Dockerfile C" {
    ch-image build-cache --reset

    ch-image build -t a -f bucache/a.df .
    ch-image build -t b -f bucache/b.df .
    sleep 1
    ch-image build -t c -f bucache/c.df .

    blessed_out=$(cat << 'EOF'
*  (c) RUN echo qux
| *  (b) RUN echo baz
| *  (a) RUN echo bar
|/
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}c"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.4.1 two pulls, same" {
    skip  "developer skip" # FIXME
    ch-image build-cache --reset

    ch-image pull alpine:3.9
    ch-image pull alpine:3.9

    blessed_out=$(cat << 'EOF'
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.4.2 two pulls, different" {
    skip  "developer skip" # FIXME

    # This test is tricky because there's no good way to ensure the repository
    # image changes. I thought we could simulate it by pulling e.g.
    # alpine:latest but calling it alpine:3.9, but pull doesn't let you state
    # a different destination reference. (The second argument is currently a
    # filesystem directory.)
}

@test "${tag}/§3.6.1 rebuild A" {
    # Forcing a rebuild show produce a new pair of FOO and BAR commits from
    # from the alpine branch.
    blessed_out=$(cat << 'EOF'
*  (a) RUN echo bar
*  RUN echo foo
| *  (c) RUN echo qux
| | *  (b) RUN echo baz
| | *  RUN echo bar
| |/
| *  RUN echo foo
|/
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    ch-image --bucache=rebuild build -t a -f bucache/a.df .
    run ch-image build-cache --tree
    [[ $status -eq 0 ]]
    echo "$output"
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.6.2 rebuild B" {
    # Rebuild of B. Since A was rebuilt in the last test, and because
    # the rebuild behavior only forces misses on non-FROM instructions, it
    # should now be based on A's new commits.
    blessed_out=$(cat << 'EOF'
*  (b) RUN echo baz
*  (a) RUN echo bar
*  RUN echo foo
| *  (c) RUN echo qux
| | *  RUN echo baz
| | *  RUN echo bar
| |/
| *  RUN echo foo
|/
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    ch-image --bucache=rebuild build -t b -f bucache/b.df .
    run ch-image build-cache --tree
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.6.3 rebuild C" {
    # Rebuild C. Since C doesn't reference img_a (like img_b does) rebuilding
    # causes a miss on FOO. Thus C makes new FOO and QUX commits.
    #
    # Shouldn't FOO hit? --reidpr 2/16
    #  - No! Rebuild forces misses; since c.df has it's own FOO it should miss.
    #     --jogas 2/24
    blessed_out=$(cat << 'EOF'
*  (c) RUN echo qux
*  RUN echo foo
| *  (b) RUN echo baz
| *  (a) RUN echo bar
| *  RUN echo foo
|/
| *  RUN echo qux
| | *  RUN echo baz
| | *  RUN echo bar
| |/
| *  RUN echo foo
|/
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    ch-image --bucache=rebuild build -t c -f bucache/c.df .
    run ch-image build-cache --tree
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}

@test "${tag}/§3.7 change then revert" {
    ch-image build-cache --reset

    ch-image build -t e -f bucache/a.df .
    # “change” by using a different Dockerfile
    sleep 1
    ch-image build -t e -f bucache/c.df .

    blessed_out=$(cat << 'EOF'
*  (e) RUN echo qux
| *  RUN echo bar
|/
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}revert1"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)

    # “revert change”; no need to check for miss b/c it will show up in graph
    ch-image build -t e -f bucache/a.df .

    blessed_out=$(cat << 'EOF'
*  RUN echo qux
| *  (e) RUN echo bar
|/
*  RUN echo foo
*  (alpine+3.9) PULL alpine:3.9
*  (HEAD -> root) root
EOF
)
    run ch-image build-cache --tree --dot="${dot_base}revert2"
    echo "$output"
    [[ $status -eq 0 ]]
    diff -u <(echo "$blessed_out") <(echo "$output" | treeonly)
}
