#include "clipping.h"
#include <stdio.h>

#define DISCARD_INTER(px, py, qx, qy, minX, minY, maxX, maxY) \
                (( ((((px) < (minX)) << 3) | (((px) > (maxX)) << 2) | (((py) < (minY)) << 1) | ((py) > (maxY))) & \
                  ((((qx) < (minX)) << 3) | (((qx) > (maxX)) << 2) | (((qy) < (minY)) << 1) | ((qy) > (maxY))) ) != 0 )

#define MIN(a,b) ( (a) < (b) ? (a) : (b) )
#define MAX(a,b) ( (a) > (b) ? (a) : (b) )


/**
  * Create a new linked lyst from floating points values pointed by @polygon
  * of size @n and return it into a pointer pointed by @l
  */
void createList(int origin, double *polyx, double *polyy, int n, struct vertex **l)
{
    int i;
    struct vertex *list = (struct vertex *) malloc (sizeof(struct vertex));
    struct vertex *prev = NULL;
    struct vertex *current = list;

    // ignore last point which must be equal to the first point
    n = n-1;

    for (i = 0; i < n-1; i++) {
        current->x = polyx[i];
        current->y = polyy[i];
        current->o = origin;
        current->prev = prev;
        current->next = (struct vertex *) malloc (sizeof(struct vertex));
        current->nextVertex = current->next;
        current->nextPoly = NULL;
        current->intersect = 0;
        prev = current;
        current = current->next;
    }

    current->x = polyx[i];
    current->y = polyy[i];
    current->o = origin;
    current->prev = prev;
    current->next = list;
    current->nextPoly = NULL;
    current->intersect = 0;
    current->nextVertex = list;
    list->prev = current;

    *l = list;
}

/**
  * Delete linked-list
  */
void deleteList(struct vertex *l)
{
    struct vertex *aux = l->next;
    l->prev->next = NULL;
    while (aux) {
        free(l);
        l = aux;
        aux = aux->next;
    }
    free(l);
}

void deletePolygons(struct vertex *poly)
{
    struct vertex *aux, *l;
    struct vertex *paux;

    paux = poly;
    while (paux) {
        l = paux;
        paux = paux->nextPoly;

        aux = l->next;
        while (aux) {
            free(l);
            l = aux;
            aux = aux->next;
        }
        free(l);
    }
}


// TODO: add perturbations in case alphaP or alphaQ = 0
int intersect(struct vertex *p1, struct vertex *p2,
    struct vertex *q1, struct vertex *q2, double *alphaP, double *alphaQ)
{
    double wec_p1, wec_p2, wec_q1, wec_q2;
    wec_p1 = (p1->x - q1->x)*(q1->y - q2->y) + (p1->y - q1->y)*(q2->x - q1->x);
    wec_p2 = (p2->x - q1->x)*(q1->y - q2->y) + (p2->y - q1->y)*(q2->x - q1->x);

    if (wec_p1 * wec_p2 <= 0)
    {
        wec_q1 = (q1->x - p1->x)*(p1->y - p2->y) + (q1->y - p1->y)*(p2->x - p1->x);
        wec_q2 = (q2->x - p1->x)*(p1->y - p2->y) + (q2->y - p1->y)*(p2->x - p1->x);

        if (wec_q1 * wec_q2 <= 0)
        {
            *alphaP = wec_p1/(wec_p1 - wec_p2);
            *alphaQ = wec_q1/(wec_q1 - wec_q2);
            int ok =  ((wec_p1 - wec_p2) != 0)
                   && ((wec_q1 - wec_q2) != 0)
                   && (*alphaP != 0) && (*alphaP != 1)
                   && (*alphaQ != 0) && (*alphaQ != 1);
            if (!ok) {
                printf("clipping degeneracy: alphaP = %f, alphaQ = %f\n",*alphaP, *alphaQ);
                exit(1);
            }
            return 1;
        }
    }

    return 0;
}

/**
  * Find and add intersection points between @lclip and @lsubject
  */
int findIntersections(struct vertex *lclip, struct vertex *lsubject)
{
    double a, b;
    int intersections = 0;
    struct vertex *aux, *v, *w, *sort;
    for (v = lsubject; v; v = v->nextVertex == lsubject ? NULL : v->nextVertex)
        for (w = lclip; w; w = w->nextVertex == lclip ? NULL : w->nextVertex)
            if (!DISCARD_INTER(v->x, v->y, v->nextVertex->x, v->nextVertex->y,
                                MIN(w->x, w->nextVertex->x), MIN(w->y, w->nextVertex->y),
                                MAX(w->x, w->nextVertex->x), MAX(w->y, w->nextVertex->y))
                && intersect(v, v->nextVertex, w, w->nextVertex, &a, &b))
            {
                // create intersection points
                struct vertex *i1 =
                    (struct vertex *) malloc (sizeof(struct vertex));
                struct vertex *i2 =
                    (struct vertex *) malloc (sizeof(struct vertex));

                intersections++;

                i1->alpha = a;
                i2->alpha = b;
                i2->x = i1->x = w->x + b * (w->nextVertex->x - w->x);
                i2->y = i1->y = w->y + b * (w->nextVertex->y - w->y);

                i1->o = 31;
                i2->o = 32;

                i1->intersect = 1;
                i2->intersect = 1;
                i1->processed = 0;
                i2->processed = 0;

                // link intersection points
                i1->neighbour = i2;
                i2->neighbour = i1;

                // sort intersection points into polygons
                sort = v;
                while (sort->next && sort->next->intersect
                    && sort->next->alpha < i1->alpha)
                    sort = sort->next;

                aux = sort->next;
                sort->next = i1;
                i1->next = aux;
                aux->prev = i1;
                i1->prev = sort;


                sort = w;
                while (sort->next && sort->next->intersect
                    && sort->next->alpha < i2->alpha)
                    sort = sort->next;

                aux = sort->next;
                sort->next = i2;
                i2->next = aux;
                aux->prev = i2;
                i2->prev = sort;
            }

    return intersections;
}

/**
  * Determine whether point @p is inside of polygon @polygon or not
  */
int isInside(struct vertex *p, struct vertex *polygon)
{
    int oddNodes = 0;
    const double x = p->x;
    const double y = p->y;
    struct vertex *node1, *node2, *q;

    for (q = polygon; q; q = q->nextVertex == polygon ? NULL : q->nextVertex)
    {
        node1 = q;

        if (q->nextVertex)
            node2 = q->nextVertex;
        else
            node2 = polygon;

        if ((node1->y < y && node2->y >= y) ||
            (node2->y < y && node1->y >= y))
        {
            if (node1->x + (y - node1->y)/
                (node2->y - node1->y) * (node2->x - node1->x) < x)
                oddNodes = !oddNodes;
        }
    }

    return oddNodes;
}

/**
  * Mark intersection points in polygon @p
  * depending on whether it's an entry or exit point
  * with respect the @interior_exterior of polygon @q
  */
void markEntries(struct vertex *p, struct vertex *q, int interior_exterior)
{
    int status;

    if (isInside(p, q))
        status = interior_exterior == POLYGON_INTERIOR ?
                                STATUS_ENTRY : STATUS_EXIT;
    else
        status = interior_exterior == POLYGON_INTERIOR ?
                                STATUS_EXIT : STATUS_ENTRY;
    struct vertex *pi;
    for (pi = p->next; pi != p; pi = pi->next)
    {
        if (pi->intersect)
        {
            pi->entry_exit = status;
            pi->processed = 0;
            status = !status;
        }
    }
}

/**
  * Adds a new polygon to a previous one pointed by @lastPoly
  * with starting vertex @p
  */
struct vertex * newPolygon(struct vertex *lastPoly, struct vertex *p)
{
    struct vertex *poly = (struct vertex *) malloc (sizeof(struct vertex));
    poly->x = p->x;
    poly->y = p->y;
    poly->o = p->o;
    poly->nextPoly = NULL;
    poly->next = NULL;

    if (lastPoly)
        lastPoly->nextPoly = poly;
    return poly;

}

/**
  * Adds new vertex to a previous one pointed by @last
  */
void newVertex(struct vertex *last, struct vertex *p)
{
    struct vertex *point =
        last->next = (struct vertex *) malloc (sizeof(struct vertex));
    point->x = p->x;
    point->y = p->y;
    point->o = p->o;

    point->next = NULL;
    point->nextPoly = NULL;

}


/**
  * Intersect the subject polygon using clip polygon and store into
  * polygons structure, returns the total number of polygons.
  */
int createClippedPolygon(struct vertex *lclip, struct vertex *lsubject,
            struct vertex **polygons, int *total)
{
    struct vertex *isubject = lsubject->next, *current;
    struct vertex *poly = NULL, *first = NULL;
    int npolys = 0;
    int nvertex = 0;

    while (isubject)
    {
        for (; isubject != lsubject && !(isubject->intersect && !isubject->processed);
                isubject = isubject->next);

        if (isubject == lsubject)
            break;

        isubject->processed = 1;
        current = isubject;

        if (first == NULL)
        {
            first = (struct vertex *) malloc (sizeof(struct vertex));
            first->x = current->x;
            first->y = current->y;
            first->o = current->o;
            first->nextPoly = NULL;
            poly = first;
        }
        else
            poly = newPolygon(poly, current);

        npolys++;
        nvertex++;

        struct vertex *lastPoint = poly;

        do {
            if (current->entry_exit == STATUS_ENTRY)
                do {
                    current = current->next;
                    newVertex(lastPoint, current);
                    lastPoint = lastPoint->next;
                    nvertex++;
                } while (!current->intersect);
            else
                do {
                    current = current->prev;
                    newVertex(lastPoint, current);
                    lastPoint = lastPoint->next;
                    nvertex++;
                } while (!current->intersect);

            current->processed = 1;
            current = current->neighbour;
            current->processed = 1;

        } while (! (poly->x == current->x && poly->y == current->y) );


    }
    if (polygons)
        *polygons = first;

    if (total)
        *total = nvertex;
    return npolys;
}


/**
  * Copy the polygons structure into an array of double-precision floats
  * containing the coordinates of each point from the resulting clipped polygon
  * return parameters are:
  * @polys: array of vertex for all the polygons
  * @lengths: array of lengths for each polygon
  */
void copy(struct vertex *polygons, int npolys, int nvertex,
                double **polysx, double **polysy, int ** origin, int **lengths)
{
    double *px = (double *) malloc (nvertex * sizeof(double));
    double *py = (double *) malloc (nvertex * sizeof(double));
    int    *po = (int *)    malloc (nvertex * sizeof(int));
    int *ls = (int *) malloc (npolys * sizeof(int));
    int polycount = 0, vertexcount = 0;
    struct vertex *ipoly, *ivertex;
    //int i,offset;
    int curlen;

    for (ipoly = polygons; ipoly; ipoly = ipoly->nextPoly)
    {
        ls[polycount] = 0;
        curlen = 0;
        for (ivertex = ipoly; ivertex; ivertex = ivertex->next)
        {
            ls[polycount]++;
            po[vertexcount] = ivertex->o;
            px[vertexcount] = ivertex->x;
            py[vertexcount++] = ivertex->y;
            curlen++;
        }
        // Last (repeated) vertex copies its origin label to first one (which was initiall "flipped").
        po[vertexcount-curlen] = po[vertexcount-1];
        polycount++;
    }
    *polysx = px;
    *polysy = py;
    *origin = po;
    *lengths = ls;
}


// Perform clipping of the polygon clip with nc points against
// a subject with ns points. Returns a set of nl polygons with specified lengths
// in an array of coordinates polys.
int clip(double *clipx, double *clipy, int nc,
            double *subjectx, double *subjecty, int ns,
                double **polysx, double **polysy, int **origin, int **lengths, int *nl, int *nlp, int *inside, int op)
{
    struct vertex *lclip, *lsubject;
    struct vertex *polygons = NULL, *polygons2 = NULL, *auxpoly = NULL;
    int cIntExt=0, sIntExt=0;
    int nvertex, nvertex2, npolys, npolys2;

    // create data structures
    createList(1,clipx, clipy, nc, &lclip);
    createList(2,subjectx, subjecty, ns, &lsubject);

    //printf("created lists\n");

    // phase one of the algorithm
    findIntersections(lclip, lsubject);

    //printf("found intersections\n");

    switch(op) {
        case POLYGON_UNION:
            cIntExt = sIntExt = POLYGON_INTERIOR;
            break;
        case POLYGON_INTERSECTION:
            cIntExt = sIntExt = POLYGON_EXTERIOR;
            break;
        case POLYGON_DIFF_AB:
            cIntExt = POLYGON_EXTERIOR;
            sIntExt = POLYGON_INTERIOR;
            break;
        case POLYGON_XOREXT:
            cIntExt = POLYGON_EXTERIOR;
            sIntExt = POLYGON_INTERIOR;
            break;
        case POLYGON_DIFF_BA:
            cIntExt = POLYGON_INTERIOR;
            sIntExt = POLYGON_EXTERIOR;
            break;
        }

    markEntries(lclip, lsubject, sIntExt);
    markEntries(lsubject, lclip, cIntExt);

    //printf("marked entries\n");

    // phase three of the algorithm
    npolys = createClippedPolygon(lclip, lsubject, &polygons, &nvertex);

    if(op==POLYGON_XOREXT && npolys > 0) {
        cIntExt = POLYGON_INTERIOR;
        sIntExt = POLYGON_EXTERIOR;

        markEntries(lclip, lsubject, sIntExt);
        markEntries(lsubject, lclip, cIntExt);

        npolys2 = createClippedPolygon(lclip, lsubject, &polygons2, &nvertex2);

        // number of "positive" polygons:
        *nlp = npolys;

        npolys += npolys2;
        nvertex += nvertex2;

        auxpoly = polygons;
        while(auxpoly->nextPoly)
            auxpoly = auxpoly->nextPoly;
        auxpoly->nextPoly = polygons2;

    } else {
        // only xorext operation uses nlp:
        *nlp = 0;
    }

    //printf("clip polygon\n");

    
    // copy polygons into polys array
    copy(polygons, npolys, nvertex, polysx, polysy, origin, lengths);
    *nl = npolys;

    //printf("copied\n");

    *inside = 0;
    if (isInside(lclip,lsubject)) *inside = 1;
    if (isInside(lsubject,lclip)) *inside = 2;

    // free memory
    deleteList(lclip);
    deleteList(lsubject);
    deletePolygons(polygons);

    return 0;
}

void readFromStdin(double **vclipx, double **vclipy, double **vsubjectx,
                double **vsubjecty, int *lclip, int *lsubject)
{
    int nread = scanf("%d %d\n", lclip, lsubject);
    int i;
    double *clipx = (double *) malloc ((*lclip)*sizeof(double));
    double *clipy = (double *) malloc ((*lclip)*sizeof(double));
    double *subjectx = (double *) malloc ((*lsubject)*sizeof(double));
    double *subjecty = (double *) malloc ((*lsubject)*sizeof(double));

    for (i = 0; i < (*lclip) && nread == 2; i++)
        nread = scanf("%lf %lf", &clipx[i], &clipy[i]);

    for (i = 0; i < (*lsubject) && nread == 2; i++)
        nread = scanf("%lf %lf", &subjectx[i], &subjecty[i]);

    *vclipx = clipx;
    *vclipy = clipy;
    *vsubjectx = subjectx;
    *vsubjecty = subjecty;
}


int main2(void)
{
    double *clipx, *clipy, *subjectx, *subjecty;
    int lclip, lsubject;

    readFromStdin(&clipx, &clipy, &subjectx, &subjecty, &lclip, &lsubject);

    double *polysx, *polysy;
    int * origin;
    int *lengths, inside, nl,nlp, i,j;

    clip(clipx, clipy, lclip, subjectx, subjecty, lsubject,
            &polysx, &polysy, &origin, &lengths, &nl, &nlp, &inside, POLYGON_INTERSECTION);

    int v = 0;
    for (i = 0; i < nl; i++) {
        printf("Polígono %d\n", i+1);
        printf("--------------------------\n");
        for (j = 0; j < lengths[i]; j++) {
            printf("x=%.5f, y=%.5f, o=%d\n", polysx[v], polysy[v], origin[v]);
            v++;
        }
    }

    free(clipx);
    free(clipy);
    free(subjectx);
    free(subjecty);
    free(polysx);
    free(polysy);
    free(origin);
    return 0;
}

