package app.archivewatch.android.ui.tv

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.archivewatch.android.data.CatalogItem

/** The brand orange, used for a page's eyebrow and its primary action. */
val TvAccent = Color(0xFFFF5C35)

/** Six across at 1920 is what TvDims.PosterWidth and the overscan inset allow. */
const val TV_PAGE_COLUMNS = 6

/**
 * The page shape every full-screen TV surface shares.
 *
 * It exists because of a measured defect, not a tidiness urge. Eight routes in
 * TvAppRoot still render the PHONE screen, four of them nav-rail destinations,
 * and a uiautomator dump of Surprise on a Google TV put film captions at x=32
 * and out to x=1888 against an overscan-safe band of 96..1824 — both edge
 * columns inside the 5% a television cuts — under a Material3 TopAppBar whose
 * back arrow sat at roughly (20, 30), outside the band on both axes.
 *
 * Three of those four are the same shape (a titled page over a grid), so they
 * get one scaffold rather than three near-copies. What it guarantees:
 *
 *  - the overscan inset, on every edge, once
 *  - a title at TV size with an eyebrow above it, because a viewer arriving
 *    from the rail needs to know what surface they are on from the sofa
 *  - actions as REAL focusable pills, never unlabelled icon buttons: a remote
 *    lands on a whole element and cannot aim at part of one
 *  - a fixed six-column grid, so tiles are TvDims.PosterWidth rather than
 *    whatever GridCells.Adaptive(110.dp) produces at TV width
 */
/**
 * @param compact for a SHELF page. A grid page can afford a tall header
 *   because its grid starts below the fold anyway; a shelf page cannot — the
 *   full-height header pushed Cartoons' first shelf down far enough that its
 *   captions landed at y=1008..1080, below the 1026 safe bottom, and only ONE
 *   shelf was on screen. Compact puts the title, meta and actions on one line.
 */
@Composable
fun TvPageHeader(
    eyebrow: String,
    title: String,
    meta: String?,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
    actions: @Composable RowScope.() -> Unit = {},
) {
    if (compact) {
        Row(
            modifier.padding(
                start = TvDims.OverscanH,
                end = TvDims.OverscanH,
                top = TvDims.OverscanV,
                bottom = 16.dp,
            ),
            horizontalArrangement = Arrangement.spacedBy(20.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    eyebrow,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    color = TvAccent,
                )
                Text(
                    title,
                    fontSize = 32.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White,
                )
                if (meta != null) {
                    Text(meta, fontSize = 19.sp, color = Color(0xFFB9B9B9))
                }
            }
            actions()
        }
        return
    }
    Column(modifier) {
        Text(
            eyebrow,
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = TvAccent,
            modifier = Modifier.padding(start = TvDims.OverscanH, top = TvDims.OverscanV),
        )
        Text(
            title,
            fontSize = 44.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
            modifier = Modifier.padding(start = TvDims.OverscanH, top = 4.dp),
        )
        if (meta != null) {
            Text(
                meta,
                fontSize = 22.sp,
                color = Color(0xFFB9B9B9),
                modifier = Modifier.padding(start = TvDims.OverscanH, top = 8.dp),
            )
        }
        Row(
            Modifier.padding(start = TvDims.OverscanH, top = 16.dp, bottom = 22.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            content = actions,
        )
    }
}

/** A pill a remote can land on. `primary` fills it; otherwise it is an outline. */
@Composable
fun TvActionPill(
    label: String,
    onClick: () -> Unit,
    focusRequester: FocusRequester? = null,
    primary: Boolean = false,
    exitLeftTo: FocusRequester? = null,
) {
    Box(
        Modifier
            .tvFocusable(
                onClick = onClick,
                focusRequester = focusRequester,
                shape = RoundedCornerShape(28.dp),
                exitLeftTo = exitLeftTo,
            )
            .then(
                if (primary) Modifier.background(TvAccent, RoundedCornerShape(28.dp))
                else Modifier,
            ),
    ) {
        Text(
            label,
            fontSize = 24.sp,
            fontWeight = FontWeight.Medium,
            color = if (primary) Color.Black else Color.White,
            modifier = Modifier.padding(horizontal = if (primary) 32.dp else 28.dp, vertical = 14.dp),
        )
    }
}

/** The grid every TV page uses: fixed columns, overscan-inset, rail-aware. */
@Composable
fun TvPosterGrid(
    rows: List<CatalogItem>,
    onClick: (CatalogItem) -> Unit,
    railFocus: FocusRequester? = null,
    modifier: Modifier = Modifier,
) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(TV_PAGE_COLUMNS),
        contentPadding = PaddingValues(
            start = TvDims.OverscanH,
            end = TvDims.OverscanH,
            bottom = TvDims.OverscanV,
        ),
        horizontalArrangement = Arrangement.spacedBy(20.dp),
        verticalArrangement = Arrangement.spacedBy(26.dp),
        modifier = modifier.fillMaxSize(),
    ) {
        itemsIndexed(rows, key = { _, it -> it.archiveID }) { index, item ->
            TvPosterTile(
                item = item,
                onClick = { onClick(item) },
                exitLeftTo = if (index % TV_PAGE_COLUMNS == 0) railFocus else null,
            )
        }
    }
}

/**
 * A refine chip — the TV answer to a dropdown.
 *
 * TvBrowseScreen has carried a private twin of this since it was built; this
 * is the shared one, so a second screen needing the same control does not get
 * a Material DropdownMenu instead. A menu on a television is the wrong shape
 * twice: it is a phone-sized target, and it opens a nested focus context a
 * remote has to escape. A row of chips is already the thing the viewer wants —
 * every option visible, one press each.
 */
@Composable
fun TvRefineChip(label: String, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .tvFocusable(
                onClick = onClick,
                shape = RoundedCornerShape(24.dp),
                scaleWhenFocused = 1.04f,
            )
            .background(
                if (selected) TvAccent else Color(0xFF1C1C1C),
                RoundedCornerShape(24.dp),
            )
            .padding(horizontal = 20.dp, vertical = 10.dp),
    ) {
        Text(
            label,
            fontSize = 19.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = if (selected) Color.Black else Color.White,
        )
    }
}
