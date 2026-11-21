// report.html: the "Something wrong with this film?" door every app opens,
// with ?film=<archiveID>&where=<platform version>. It fills an email (no
// account needed) and the GitHub issue form; nothing is sent from this page.
(function () {
  const q = new URLSearchParams(location.search);
  const film = (q.get('film') || '').slice(0, 200);
  const where = (q.get('where') || '').slice(0, 80);

  if (film) {
    const label = document.getElementById('report-film');
    label.textContent = film;
    label.hidden = false;
  }

  const body = (film ? 'Film: ' + film + '\n' : '') +
    (where ? 'Seen in: ' + where + '\n' : '') + '\nWhat is wrong:\n';
  const subject = 'Archive Watch: something wrong with ' + (film || 'a film');
  document.getElementById('report-email').href = 'mailto:ben@learningischange.com?subject=' +
    encodeURIComponent(subject) + '&body=' + encodeURIComponent(body);

  const gh = new URL('https://github.com/bhwilkoff/Archive-Watch/issues/new');
  gh.searchParams.set('template', 'film-problem.yml');
  if (film) gh.searchParams.set('film', film);
  if (where) gh.searchParams.set('where', where);
  document.getElementById('report-github').href = gh.toString();
})();
