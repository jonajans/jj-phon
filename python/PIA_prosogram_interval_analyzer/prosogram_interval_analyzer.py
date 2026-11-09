import argparse
import csv
import math
import os
import textwrap
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import parselmouth
from matplotlib.ticker import MaxNLocator

# Maximum duration in seconds for an utterance to be included in the histograms
# Intervals with longer duration than this will not be discarded from the analysis output
MAX_DURATION = 1.8


def read_points(path: Path) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Returns arrays w/ type, time, styl_hz, styl_st"""
    with open(path, "r", encoding="utf-8") as file:
        rows = [
            token
            for token in map(str.split, file)  # split each row into a list
            if token
            and token[0]
            in {
                "tstart",
                "tin",
                "tend",
            }  # only analyze rows with stylization points
        ]
    types = np.array([r[0] for r in rows])  # array w point type
    times, styl_hz, styl_st = np.array(
        [r[1:] for r in rows], dtype=float
    ).T  # transposing gives one row per point
    return types, times, styl_hz, styl_st


def analyze_intervals(path: Path, max_silence_duration: float) -> dict[str, np.ndarray]:
    """Returns a dict with one array per csv-column"""
    types, times, hz, st = read_points(path)
    midi = 12 * np.log2(hz / 440) + 69

    duration = np.diff(times)
    st_diff = np.diff(st)
    hz_diff = np.diff(hz)

    # This is used to separate intra- and intersyllabic movements
    # All intrasyll are assumed to be glissandos, as f0-discontinuities would be unreasonable
    # All intersyll are treated as jumps, which may be a limitation of the analysis
    is_inter = (types[:-1] != "tin") & (types[1:] != "tin")  # bool-array

    # If duration is between nuclei and exceed maximum duration, mark as inter-utterance
    # Base value is 1.8 s, which roughly corresponded to the common time between utterances in
    # the SweDia corpus which the script was developed for analyzing
    inter_utt = is_inter & (duration >= max_silence_duration)

    # Normalize intervals larger than one octave into the range ±12 st
    octave_error = np.abs(st_diff) > 12
    st_diff_norm = np.where(
        octave_error, np.sign(st_diff) * (np.abs(st_diff) % 12), st_diff
    )

    size_hz_norm = np.where(
        octave_error, hz[:-1] * 2 ** (st_diff_norm / 12) - hz[:-1], hz_diff
    )

    slope = st_diff / duration
    slope_norm = st_diff_norm / duration
    dynamic = st_diff != 0

    print(
        f"Found {dynamic.sum()} dynamic segments, {(~dynamic).sum()} static segments, "
        f"{inter_utt.sum()} inter-utterance segments, and {octave_error.sum()} larger than one octave (12 ST)\n"
        f"Mean of interval F0 start is {np.mean(st[:-1])} ST re. 1 Hz, stdev {np.std(st[:-1])}."
    )

    return {
        "type": np.where(is_inter, "intersyll", "intrasyll"),
        "start_time_s": times[:-1],
        "end_time_s": times[1:],
        "duration_s": duration.round(4),
        "from_hz": hz[:-1].round(4),
        "from_st": st[:-1],
        "from_midi": midi[:-1].round(4),
        "to_hz": hz[1:].round(4),
        "to_st": st[1:],
        "to_midi": midi[1:].round(4),
        "size_hz": np.diff(hz).round(4),
        "size_hz_norm": size_hz_norm.round(4),
        "size_st": st_diff.round(4),
        "size_st_norm": st_diff_norm.round(4),
        "slope_st_per_s": slope.round(4),
        "slope_st_per_s_norm": slope_norm.round(4),
        "dynamic": dynamic.astype(int),
        "inter_utterance": inter_utt.astype(int),
        "octave_error": octave_error.astype(int),
    }


def calculate_bins(sizes: np.ndarray, is_st: bool) -> tuple[list[float], int]:
    """Used to determine bin bounds of the histograms.

    Parameters:
    sizes: ndarray with all interval sizes
    is_st: True if sizes has unit ST, False if it has unit Hz

    Returns:
    (list[float] with bounds for all bins, int with the bound without sign)"""
    max_abs = np.abs(sizes).max()

    if is_st:
        bins_bound = int(np.ceil(max_abs))
        bins = np.arange(-bins_bound, bins_bound + 1, 1, dtype=float).tolist()
        return bins, bins_bound + 1
    else:
        bins_bound = int(math.ceil(max_abs / 10.0) * 10) or 10
        bins = np.arange(-bins_bound, bins_bound + 10, 10, dtype=float).tolist()
        return bins, bins_bound + 10


def plot_and_save_histogram(
    intervals: np.ndarray,
    title: str,
    xlabel: str,
    output_filename: str,
    output_dir: Path,
    is_st=False,
) -> None:
    """Help function for generating and saving histogram"""
    if len(intervals) == 0:
        return

    output_filepath = output_dir / output_filename
    bins, bins_bound = calculate_bins(intervals, is_st)

    plt.figure(figsize=(10, 5))

    if is_st:
        plt.hist(intervals, bins=bins, edgecolor="black", alpha=0.75, color="#1f77b4")
        plt.xlim(-bins_bound - 1, bins_bound + 1)
        plt.xticks(np.arange(-bins_bound, bins_bound + 1, 2))

    else:
        plt.hist(intervals, bins=bins, edgecolor="black", alpha=0.75, color="#1f77b4")
        plt.xlim(-bins_bound - 1, bins_bound + 1)

    # Force integer bounds
    plt.gca().yaxis.set_major_locator(MaxNLocator(integer=True))

    plt.title(title, fontsize=14)
    plt.xlabel(xlabel, fontsize=12)
    # plt.ylabel("Count", fontsize=12)
    plt.grid(axis="y", linestyle="--", alpha=0.7)
    plt.tight_layout()
    plt.savefig(output_filepath, dpi=300)
    plt.close()


def generate_histograms(
    cols: dict[str, np.ndarray],
    output_dir: Path,
    stem: str,
    save_hist_hz: bool,
    save_hist_st: bool,
) -> None:

    # np-masks
    dynamic = cols["dynamic"] == 1
    inter_utt = cols["inter_utterance"] == 1
    is_inter = cols["type"] == "intersyll"

    # Plot only intervals that are dynamic & within duration threshold
    keep_tot = dynamic & ~inter_utt
    masks = {
        "tot": keep_tot,
        "intersyll": keep_tot & is_inter,
        "intrasyll": keep_tot & ~is_inter,
    }
    titles = {
        "tot": "all intervals",
        "intersyll": "intersyllabic jumps",
        "intrasyll": "intrasyllabic glissandos",
    }

    # create plots - normalized octaves are used
    if save_hist_hz:
        for name in masks:
            plot_and_save_histogram(
                cols["size_hz_norm"][masks[name]],
                f"Histogram over {titles[name]}",
                "Interval (Hz)",
                f"{stem}_hz_{name}.png",
                output_dir,
                is_st=False,
            )

    if save_hist_st:
        for name in masks:
            plot_and_save_histogram(
                cols["size_st_norm"][masks[name]],
                f"Histogram over {titles[name]}",
                "Interval (ST)",
                f"{stem}_st_{name}.png",
                output_dir,
                is_st=True,
            )


def input_to_bool(input: str) -> bool:
    return input.strip().lower() == "y"


def run_prosogram(wav_path) -> None:
    """Stylizes the wav file at wav_path using prosogram in subdirectory"""

    print("Entering subdirectory plugin_prosogram/...")
    script_wd = Path.cwd()
    prosogram_wd = script_wd / "plugin_prosogram"
    if not prosogram_wd.is_dir():
        raise SystemExit(
            f"Directory {prosogram_wd} is missing. Please create this folder, "
            "download the Prosogram plugin for Praat, and place it there."
        )

    print("\n[Running Prosogram...]\n")
    wav_path_absolute = str(Path(wav_path).resolve())

    try:
        os.chdir(prosogram_wd)

        praat_script = textwrap.dedent("""
        form Run Prosogram
            text file_path
        endform

        include prosomain.praat
        @prosogram: "file=" + file_path$ + " save=yes draw=no"
        """).strip()

        parselmouth.praat.run(praat_script, wav_path_absolute)

        print("\n[Prosogram finished]")
        print("Exiting plugin_prosogram...\n")
    finally:
        os.chdir(script_wd)


def print_welcome_info() -> None:
    print(
        "This script takes as its input a Prosogram stylization in the .txt format,\n"
        "as detailed on p. 51f in the Prosogram User Guide (Mertens, 2022)."
    )
    print(
        "It is possible to generate this stylisation directly through this Python script,\n"
        'if you have downloaded the Prosogram script files and placed them in the subdirectory "plugin_prosogram/".'
    )

    script_wd = Path.cwd()
    prosogram_wd = script_wd / "plugin_prosogram"

    print(
        "If you plan to run the script from this directory, the script expects "
        f"those files to be located in {prosogram_wd}."
    )
    print(
        "Note that you must set a flag in prosomain.praat to export the stylization as a text\n"
        "file. This is done by setting the rich_format_stylization to 1.\n"
        "Please do so before continuing, else the script will fail."
    )

    print(
        "\nIf you have generated the stylization beforehand, you can analyze the\n"
        "result directly without re-running the stylization."
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="PIA: Prosogram interval analyzer",
        description="Analyse a Prosogram stylization by going from points to interval representation. Requires separate download of the Prosogram Praat plugin.",
        epilog="Jonathan Jansson <jonathan1jansson@gmail.com>",
    )

    parser.add_argument(
        "input",
        nargs="?",  # args optional - if not, will run interactively
        type=Path,
        help="Path to .wav-file (will run stylization through Prosogram) "
        "or to a previously created stylization *_styl.txt",
    )

    parser.add_argument(
        "--max-duration",
        type=float,
        default=MAX_DURATION,  # if not specified, use constant at top of file
        help="Maximum duration (in seconds) for interval not to be flagged as "
        f"inter-utterance. Default: {MAX_DURATION}",
    )

    args = parser.parse_args()

    if (
        args.input is not None
        and args.input.suffix.lower() != ".wav"
        and not args.input.name.endswith("_styl.txt")
    ):
        parser.error("input must be a wav or *_styl.txt file")

    return args


def main():
    args = parse_args()
    max_duration = args.max_duration

    if args.input is None:  # run interactively
        print_welcome_info()
        generate_stylization = input_to_bool(
            input("Generate Prosogram stylization? [y/n] ")
        )

        if generate_stylization:
            wav_path = Path(input("Enter path to wav file: "))

        else:
            styl_path = Path(input("Relative path to _styl.txt file: "))

    else:  # CLI usage: determine if input is sound or stylization
        generate_stylization = args.input.suffix.lower() == ".wav"

        if generate_stylization:
            wav_path = args.input

        else:
            styl_path = args.input

    if generate_stylization:
        run_prosogram(wav_path)
        styl_path = wav_path.with_name(f"{wav_path.stem}_styl.txt")

    if not styl_path.is_file():
        raise SystemExit(
            f"Cannot find {styl_path}. This can be caused by several things. Tips for troubleshooting:\n"
            "1. Ensure that Prosogram is placed in the subdirectory plugin_prosogram relative "
            "to the script file\n"
            "2. Ensure that the flag rich_format_stylization is set to 1 in prosomain.praat (see p. 51ff of the User Guide)\n"
            "3. Ensure that you entered the correct path to the wav file\n"
            "4. Check the Prosogram output above for any error messages"
        )

    print("[Running PIA]")

    # create folder name
    base_stem = styl_path.stem.removesuffix("_styl")
    output_dir = styl_path.with_name(f"{base_stem}_results")

    # create output directory if needed
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Analysis & histograms will be saved to the directory {output_dir}.")
    analysis_output_path = output_dir / f"{base_stem}_analysis.csv"

    print(
        f"Max duration of interval is set to {max_duration} s. Intervals with longer duration \n"
        "will be marked as inter-utterance and not included in the histogram plots.\n"
        "This threshold can be changed by adding the flag --max-duration [float].\n"
    )

    cols = analyze_intervals(styl_path, max_duration)

    with open(analysis_output_path, "w", newline="", encoding="utf-8") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(cols)
        writer.writerows(zip(*cols.values()))  # gives one row per interval
        print(f"Analyzed {styl_path} and saved to {analysis_output_path}")

    # Ask to generate histograms
    save_hz = input_to_bool(input("Save histograms in Hz? [y/n] "))
    save_st = input_to_bool(input("Save histograms in semitones? [y/n] "))

    if save_hz or save_st:
        generate_histograms(cols, output_dir, base_stem, save_hz, save_st)
        print("Saved histogram(s)")


if __name__ == "__main__":
    main()
