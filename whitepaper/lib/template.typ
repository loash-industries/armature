// Armature Whitepaper Template
// Styling and layout configuration

#let armature-paper(
  title: none,
  subtitle: none,
  authors: (),
  date: none,
  abstract: none,
  body,
) = {
  // Document metadata
  set document(
    title: title,
    author: authors.map(a => a.name),
  )

  // Page setup
  set page(
    paper: "a4",
    margin: (x: 2.5cm, y: 2.5cm),
    numbering: "1",
    number-align: center,
    header: context {
      if counter(page).get().first() > 1 {
        set text(8pt, fill: luma(120))
        smallcaps[Armature Project]
        h(1fr)
        smallcaps[Draft]
      }
    },
  )

  // Typography
  set text(
    font: "New Computer Modern",
    size: 11pt,
    lang: "en",
  )

  set par(
    justify: true,
    leading: 0.7em,
    first-line-indent: 1.2em,
  )

  // Heading styles
  set heading(numbering: "1.1")

  show heading.where(level: 1): it => {
    pagebreak(weak: true)
    v(1.5em)
    set text(16pt, weight: "bold")
    block(below: 1em)[
      #counter(heading).display("1") #h(0.5em) #it.body
    ]
  }

  show heading.where(level: 2): it => {
    v(1em)
    set text(13pt, weight: "bold")
    block(below: 0.7em)[
      #counter(heading).display("1.1") #h(0.5em) #it.body
    ]
  }

  show heading.where(level: 3): it => {
    v(0.8em)
    set text(11pt, weight: "bold", style: "italic")
    block(below: 0.5em)[
      #counter(heading).display("1.1.1") #h(0.5em) #it.body
    ]
  }

  // Code blocks
  show raw.where(block: true): it => {
    set text(9pt)
    block(
      fill: luma(245),
      inset: 10pt,
      radius: 3pt,
      width: 100%,
      it,
    )
  }

  show raw.where(block: false): it => {
    set text(9.5pt)
    box(
      fill: luma(240),
      inset: (x: 3pt, y: 1pt),
      radius: 2pt,
      it,
    )
  }

  // Figures
  show figure: it => {
    set text(size: 10pt)
    it
    v(0.5em)
  }

  // Links
  show link: set text(fill: rgb("#1a5276"))

  // --- Title Page ---
  {
    set page(numbering: none, header: none)
    set par(first-line-indent: 0em)

    v(1.5cm)
    align(center)[
      #image("../../assets/armature-logo.svg", width: 4cm)
    ]

    v(1.5cm)
    align(center)[
      #text(28pt, weight: "bold")[#title]
      #v(0.8cm)
      #if subtitle != none {
        text(16pt, fill: luma(80))[#subtitle]
      }
      #v(2cm)
      // Authors side by side
      #grid(
        columns: authors.len(),
        column-gutter: 2cm,
        ..authors.map(author => [
          #text(12pt)[#author.name] \
          #if "affiliation" in author {
            text(10pt, fill: luma(100))[#author.affiliation]
          }
        ])
      )
      #v(1cm)
      #if date != none {
        text(11pt, fill: luma(100))[#date]
      }
    ]

    v(2cm)

    if abstract != none {
      set par(first-line-indent: 0em)
      block(inset: (x: 2cm))[
        #text(12pt, weight: "bold")[Abstract]
        #v(0.5em)
        #text(10.5pt)[#abstract]
      ]
    }

    pagebreak()
  }

  // --- Table of Contents ---
  {
    set page(numbering: none, header: none)
    set par(first-line-indent: 0em)
    outline(depth: 3, indent: 1.5em)
    pagebreak()
  }

  // --- Body ---
  counter(page).update(1)
  body
}

// Utility: definition box
#let defbox(term, body) = {
  block(
    fill: rgb("#f8f4e8"),
    inset: 12pt,
    radius: 3pt,
    width: 100%,
    [*#term.* #body],
  )
}

// Utility: aside/note
#let aside(body) = {
  block(
    stroke: (left: 2pt + luma(180)),
    inset: (left: 12pt, y: 4pt),
    body,
  )
}

// Utility: principle box
#let principle(title, body) = {
  block(
    stroke: 1pt + luma(200),
    inset: 12pt,
    radius: 3pt,
    width: 100%,
    [
      #text(weight: "bold", size: 10pt)[#title]
      #v(0.3em)
      #body
    ],
  )
}
