/* Channels, Party Play and the Cartoon Marathon are EPHEMERAL: they are
   ambient lineups, not things you are part-way through. None may write watch
   progress, or Continue Watching fills with films nobody chose to start.

   This has been lost before. On tvOS the flag existed and the save path ran
   anyway, persisting WatchProgress every 5 seconds for exactly these three
   surfaces (fixed 2026-08-12). A flag nothing checks is not a guarantee, so
   assert BOTH halves: every ephemeral caller passes persist:false, AND the
   save path refuses when it is set.

     node tools/test_web_ephemeral.mjs
*/
import fs from "node:fs";

let pass = 0, fail = 0;
const check = (name, got, want = true) => {
  const ok = JSON.stringify(got) === JSON.stringify(want);
  ok ? pass++ : fail++;
  console.log(`  ${ok ? "ok  " : "FAIL"} ${name}${ok ? "" : `  (got ${JSON.stringify(got)})`}`);
};

const src = fs.readFileSync("watch.js", "utf8");

// 1. The save path must refuse. This is the half that failed on tvOS.
check("the progress save refuses when the context is ephemeral",
      /if \(!this\.ctx \|\| this\.ctx\.persist === false\) return;/.test(src));

// 2. Every Player.start that begins a lineup must ask for it.
const starts = [...src.matchAll(/Player\.start\(\{[^}]*\}\)/g)].map(m => m[0]);
check("there are lineup starts to check at all", starts.length >= 3);
const lineups = starts.filter(s => /queue:|queue,/.test(s));
check("every queued lineup passes persist:false",
      lineups.every(s => /persist:\s*false/.test(s)),
      true);
check("...and there are at least three of them (channels, party, marathon)",
      lineups.length >= 3, true);

// 3. Party Play is also MUTED — it is background visuals, per the apps.
const party = src.slice(src.indexOf("Party Play"), src.indexOf("Party Play") + 3000);
check("Party Play starts muted", /muted:\s*true/.test(party));

/* A TV shelf needs a FULL ROW. Measured on the live site in TV mode: NASA
   Films rendered 4 tiles, Educational Shorts and From the Silent Era 5 — on a
   1080p panel that reads as a shelf that failed to load. Roku raised its floor
   to 7 for the same complaint (F2). A phone is different: four tiles fill the
   width there, so the floor is read from the context rather than one number
   being wrong on one of them. */
{
  const shelf = src.slice(src.indexOf("const shelfSection"),
                          src.indexOf("host.append(this.categoryTiles())"));
  check("the shelf floor depends on whether this is a TV",
        /classList\.contains\('tv'\)/.test(shelf) && /\? 7 : 4/.test(shelf));
  check("...and a shelf under the floor renders nothing at all",
        /rows\.length < floor\) return document\.createDocumentFragment\(\)/.test(shelf));
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
