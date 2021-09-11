# Doc

The **last** site generator I will ever write.

## How it works

Doc looks for a `_pages` directory in the current directory *(unless `-d` is passed)*. This folder should contain posts and basic template files (using the convention below). It will then generate Markdown, HTML, or Plaintext documents using those files.

## File naming convention

Doc expects a few files to use as templates when generating:

- `index.page.(html|markdown|plaintext)`: The index/home page template for generated output.
- `post.page.(html|markdown|plaintext)`: The template for each 'post' file.

Note: These files have to be created for each output format you wish to use. Standalone pages can be generated using the same convention: `name.page.output-format`.

Posts (content files for the generator) use the `.post` extension. Posts not ending in this extension will be ignored (ex. `test.post.draft`).

## Post format overview

Because Doc can output different "display" formats, posts have their own special syntax that's relatively easy to use and allows a bit of control over the output. Think more than Markdown but less than HTML.

Post files consist of "tags" contain the actual post content. Tags have the following syntax: `\tag(-attribute)*{value of tag}`. In practice, it looks like this:

```tex
\text { Lorem \bold{ipsum} dolor \bold-italic{sit amet}. }
```

Note: Attributes are optional, can be chained with `-`, and can be applied in any order. In Markdown and HTML, the above example would generate:

```html
<span>Lorem <strong>ipsum</strong> dolor <strong><em>sit amet</em></strong>.</span>
```

```markdown
Lorem **ipsum** dolor ***sit amet***.
```

Tags always need `{}` regardless of if they require a value (example: `\dash{}`).

### Available tags:

```tex
\... Meta tags
\. These tags give information to the generator before the final pages are created.

\meta-title  { title of post }
\meta-date   { 01/01/2021    } \. Available Formats: Year/Month/Day, Day/Month/Year, Month/Day/Year
\meta-edited { 01/01/2021    } \. Same as \meta-date
\meta-kind   { blog update   } \. Space-separated categories

\... Content Tags

\dash          {}                     \. Default size: Large
\break         {}
\separator     {}
\header        { value of header    } \. Default size: Large
\paragraph     { value of paragraph }
\link          { url value of link  } \. Example: \link{ https://github.com GitHub Homepage }
\code-language { value of block     } \. Languages: c, go, jai, javascript, lua, python
\text          { value of text      }
\quote         { value of quote     } \. Adds correct quotation around its value

\... Attribute Tags
\. These tags can, but are not meant to, be used on their own.
\. They should usually modify other tags like: \text, \paragraph, etc.

\small     {}                    \. Modifies the size of an element (ex. an <h3>) 
\medium    {}                    \. Modifies the size of an element (ex. an <h2>)
\large     {}                    \. Modifies the size of an element (ex. an <h1>)
\bold      { text to bold      }
\italic    { text to italicize }
\underline { text to underline }
\monospace { monospace text    } \. Where \code generates a block, \monospace is inline

\... Conditional Tags
\. These tags allow some content to be included for specific formats.
\. For clarity, an optional \format tag can prefix these.

\html      { html-only content      }
\markdown  { markdown-only content  }
\plaintext { plaintext-only content }
```

### Minor annoyances

Because `\\`, `{`, and `}` are special characters, they must be escaped if the actual value is needed. This is especially annoying when writing code blocks in languages like C:

```tex
\code-c {
    int
    main(int argc, char* argv[])
    \{
        printf("Hello, World\\n");
    \}
}
```

I might get around to making this less annoying in the future.

## Templating

A special subset of tags exist for templating purposes.

```tex
\title    {}                  \. The title of the post (as specified by \meta-title)
\date     { [format string] } \. Example: \date{ Posted: [format string] }
\edited   { [format string] } \. Same as \date
\posts    { [format string] } \. Example: \posts{ <li>[format string]</li> }
\contents {}                  \. The generated content of the post
\include  { file to include } \. Includes a file (within _pages/include) directly. Note: the file will not processed

\. Certain tags can be given a format string to change how the content is generated.
\. The format string has similar syntax to 'printf' in C, however, changes depending on what tag it's affecting.

\. Options for \date, \edited:
    \. %Y - 4 digit padded year (ex. 2021)
    \. %y - 2 digit padded year (ex. 21)
    \. %M - 2 digit padded month (ex. 10)
    \. %m - Written name of month (ex. October)
    \. %D - 2 digit padded day (ex. 04)
    \. %d - 0 digit padded day (ex. 4)

\. Options \posts:
    \. %u - Canonical 'url' of post (can be used as link)
    \. %t - Title of post
```

## Closing

To see how the generator is actually used in practice, check out the [repository for my website](https://github.com/judah-caruso/judah-caruso.github.io).

## License

MIT