// Regenerate Notices/GRAMMAR-LICENSES.md using `make syntax-notices`.
fn main() {
    println!("# Grammar licenses from two-face 0.5.2+bat-0.26.1\n");
    println!(
        "Extracted from the pinned crate's embedded acknowledgements. This is a\nsuperset: it includes notices for syntaxes excluded by the fancy-regex bundle.\nNo two-face themes are used by Kasumi.\n"
    );
    println!(
        "Upstream provenance: {}\n",
        two_face::acknowledgement::url()
    );
    for license in two_face::acknowledgement::listing().for_syntaxes() {
        let mut text = String::new();
        license.write_md(&mut text);
        print!("{text}");
    }
}
