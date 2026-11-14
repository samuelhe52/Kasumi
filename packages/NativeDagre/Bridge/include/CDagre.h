#ifndef KASUMI_CDAGRE_H
#define KASUMI_CDAGRE_H
#include <stddef.h>
#include <stdint.h>

/* All coordinates use a top-left origin; node coordinates are centers.
 * Inputs are borrowed only for the duration of td_dagre_layout. The returned
 * result owns its storage and must be freed exactly once. All getter outputs
 * are copies; an unsuccessful getter leaves its output untouched. */
typedef struct { double x, y; } TDPoint;
typedef struct { double width, height; int32_t parent_index; } TDNodeInput;
typedef struct {
    uint32_t source, target;
    double label_width, label_height, label_offset;
    int32_t min_length, weight;
    uint32_t label_position; /* 0=center, 1=left, 2=right */
} TDEdgeInput;
typedef struct {
    double node_separation, edge_separation, rank_separation, margin_x, margin_y;
    uint32_t direction; /* 0=TB, 1=BT, 2=LR, 3=RL */
    uint32_t tie_keep_first;
    uint32_t ranker; /* 0=network simplex, 1=tight tree, 2=longest path */
    uint32_t alignment; /* 0=automatic, 1=UL, 2=UR, 3=DL, 4=DR */
    uint32_t rank_alignment; /* 0=center, 1=top, 2=bottom */
    uint32_t greedy_acyclicer;
} TDOptions;
typedef struct { double x, y, width, height; } TDNodeOutput;
typedef struct {
    double label_x, label_y;
    uint32_t has_label_center;
    size_t point_count;
} TDEdgeOutput;
typedef struct TDDagreResult TDDagreResult;

/* 0=success, 1=invalid input, 2=layout panic, 3=invalid layout output.
 * At most 4096 nodes and 16384 edges. Nonzero counts require valid arrays.
 * Parent indices are -1 or a node index; parent relationships must be acyclic.
 * All dimensions/separations must be finite, nonnegative, and <= 1e9. */
int32_t td_dagre_layout(const TDNodeInput *nodes, size_t node_count,
                       const TDEdgeInput *edges, size_t edge_count,
                       const TDOptions *options, TDDagreResult **result);
void td_dagre_result_free(TDDagreResult *result);
int32_t td_dagre_result_node(const TDDagreResult *result, size_t index, TDNodeOutput *node);
int32_t td_dagre_result_edge(const TDDagreResult *result, size_t index, TDEdgeOutput *edge);
int32_t td_dagre_result_point(const TDDagreResult *result, size_t edge_index, size_t point_index, TDPoint *point);
int32_t td_dagre_result_size(const TDDagreResult *result, TDPoint *size);
#endif
