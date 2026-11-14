use dagre::{
    graph::{Graph, GraphOptions},
    layout::types::LabelPos,
    *,
};
use std::{
    panic::{AssertUnwindSafe, catch_unwind},
    slice,
};

#[repr(C)]
#[derive(Clone, Copy)]
pub struct TDPoint {
    x: f64,
    y: f64,
}
#[repr(C)]
pub struct TDNodeInput {
    width: f64,
    height: f64,
    parent_index: i32,
}
#[repr(C)]
pub struct TDEdgeInput {
    source: u32,
    target: u32,
    label_width: f64,
    label_height: f64,
    label_offset: f64,
    min_length: i32,
    weight: i32,
    label_position: u32,
}
#[repr(C)]
pub struct TDOptions {
    node_separation: f64,
    edge_separation: f64,
    rank_separation: f64,
    margin_x: f64,
    margin_y: f64,
    direction: u32,
    tie_keep_first: u32,
    ranker: u32,
    alignment: u32,
    rank_alignment: u32,
    greedy_acyclicer: u32,
}
#[repr(C)]
#[derive(Clone, Copy)]
pub struct TDNodeOutput {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}
#[repr(C)]
#[derive(Clone, Copy)]
pub struct TDEdgeOutput {
    label_x: f64,
    label_y: f64,
    has_label_center: u32,
    point_count: usize,
}
pub struct TDDagreResult {
    nodes: Vec<TDNodeOutput>,
    edges: Vec<(TDEdgeOutput, Vec<TDPoint>)>,
    size: TDPoint,
}

fn dimension(v: f64) -> bool {
    v.is_finite() && (0.0..=1e9).contains(&v)
}
fn validate(nodes: &[TDNodeInput], edges: &[TDEdgeInput], o: &TDOptions) -> bool {
    if ![
        o.node_separation,
        o.edge_separation,
        o.rank_separation,
        o.margin_x,
        o.margin_y,
    ]
    .into_iter()
    .all(dimension)
        || o.direction > 3
        || o.tie_keep_first > 1
        || o.ranker > 2
        || o.alignment > 4
        || o.rank_alignment > 2
        || o.greedy_acyclicer > 1
    {
        return false;
    }
    for (i, n) in nodes.iter().enumerate() {
        if !dimension(n.width)
            || !dimension(n.height)
            || n.parent_index < -1
            || n.parent_index >= nodes.len() as i32
        {
            return false;
        }
        let mut ancestor = n.parent_index;
        let mut depth = 0;
        while ancestor >= 0 {
            if ancestor as usize == i || depth >= nodes.len() {
                return false;
            }
            // Validate every hop before indexing, including parents not visited yet.
            if ancestor as usize >= nodes.len() {
                return false;
            }
            ancestor = nodes[ancestor as usize].parent_index;
            if ancestor < -1 {
                return false;
            }
            depth += 1;
        }
    }
    edges.iter().all(|e| {
        (e.source as usize) < nodes.len()
            && (e.target as usize) < nodes.len()
            && [e.label_width, e.label_height, e.label_offset]
                .into_iter()
                .all(dimension)
            && (1..=1000).contains(&e.min_length)
            && (0..=1_000_000).contains(&e.weight)
            && e.label_position <= 2
    })
}

fn run(nodes: &[TDNodeInput], edges: &[TDEdgeInput], o: &TDOptions) -> Result<TDDagreResult, i32> {
    if !validate(nodes, edges, o) {
        return Err(1);
    }
    if nodes.is_empty() {
        return Ok(TDDagreResult {
            nodes: vec![],
            edges: vec![],
            size: TDPoint { x: 0.0, y: 0.0 },
        });
    }
    let mut graph = Graph::with_options(GraphOptions {
        directed: true,
        multigraph: true,
        compound: nodes.iter().any(|n| n.parent_index >= 0),
    });
    for (i, n) in nodes.iter().enumerate() {
        graph.set_node(
            i.to_string(),
            Some(NodeLabel {
                width: n.width,
                height: n.height,
                ..Default::default()
            }),
        );
    }
    for (i, n) in nodes.iter().enumerate() {
        if n.parent_index >= 0 {
            graph.set_parent(&i.to_string(), Some(&n.parent_index.to_string()));
        }
    }
    for (i, e) in edges.iter().enumerate() {
        graph.set_edge(
            e.source.to_string(),
            e.target.to_string(),
            Some(EdgeLabel {
                width: e.label_width,
                height: e.label_height,
                label_offset: e.label_offset,
                minlen: e.min_length,
                weight: e.weight,
                labelpos: match e.label_position {
                    1 => LabelPos::Left,
                    2 => LabelPos::Right,
                    _ => LabelPos::Center,
                },
                ..Default::default()
            }),
            Some(&i.to_string()),
        );
    }
    layout(
        &mut graph,
        Some(LayoutOptions {
            rankdir: match o.direction {
                1 => RankDir::BT,
                2 => RankDir::LR,
                3 => RankDir::RL,
                _ => RankDir::TB,
            },
            nodesep: o.node_separation,
            edgesep: o.edge_separation,
            ranksep: o.rank_separation,
            marginx: o.margin_x,
            marginy: o.margin_y,
            tie_keep_first: o.tie_keep_first != 0,
            ranker: match o.ranker {
                1 => Ranker::TightTree,
                2 => Ranker::LongestPath,
                _ => Ranker::NetworkSimplex,
            },
            align: match o.alignment {
                1 => Some(Align::UL),
                2 => Some(Align::UR),
                3 => Some(Align::DL),
                4 => Some(Align::DR),
                _ => None,
            },
            rank_align: match o.rank_alignment {
                1 => RankAlign::Top,
                2 => RankAlign::Bottom,
                _ => RankAlign::Center,
            },
            acyclicer: if o.greedy_acyclicer != 0 {
                Some(Acyclicer::Greedy)
            } else {
                None
            },
        }),
    );
    let mut output_nodes = Vec::with_capacity(nodes.len());
    for i in 0..nodes.len() {
        let n = graph.node(&i.to_string()).ok_or(3)?;
        let (x, y) = (n.x.ok_or(3)?, n.y.ok_or(3)?);
        if ![x, y, n.width, n.height].into_iter().all(f64::is_finite) {
            return Err(3);
        }
        output_nodes.push(TDNodeOutput {
            x,
            y,
            width: n.width,
            height: n.height,
        });
    }
    let mut output_edges = Vec::with_capacity(edges.len());
    for (i, input) in edges.iter().enumerate() {
        let e = graph
            .edge(
                &input.source.to_string(),
                &input.target.to_string(),
                Some(&i.to_string()),
            )
            .ok_or(3)?;
        let points: Vec<_> = e
            .points
            .iter()
            .map(|p| TDPoint { x: p.x, y: p.y })
            .collect();
        if points.iter().any(|p| !p.x.is_finite() || !p.y.is_finite()) {
            return Err(3);
        }
        let center = match (e.x, e.y) {
            (Some(x), Some(y)) if x.is_finite() && y.is_finite() => Some((x, y)),
            (None, None) => None,
            _ => return Err(3),
        };
        output_edges.push((
            TDEdgeOutput {
                label_x: center.map_or(0.0, |p| p.0),
                label_y: center.map_or(0.0, |p| p.1),
                has_label_center: center.is_some() as u32,
                point_count: points.len(),
            },
            points,
        ));
    }
    let label = graph.graph_label::<GraphLabel>().ok_or(3)?;
    if ![label.width, label.height].into_iter().all(dimension) {
        return Err(3);
    }
    Ok(TDDagreResult {
        nodes: output_nodes,
        edges: output_edges,
        size: TDPoint {
            x: label.width,
            y: label.height,
        },
    })
}

/// Pointer arguments follow the contract declared in Bridge/include/CDagre.h.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn td_dagre_layout(
    nodes: *const TDNodeInput,
    node_count: usize,
    edges: *const TDEdgeInput,
    edge_count: usize,
    options: *const TDOptions,
    result: *mut *mut TDDagreResult,
) -> i32 {
    if result.is_null() {
        return 1;
    }
    unsafe {
        *result = std::ptr::null_mut();
    }
    if options.is_null()
        || node_count > 4096
        || edge_count > 16384
        || (node_count > 0 && nodes.is_null())
        || (edge_count > 0 && edges.is_null())
    {
        return 1;
    }
    catch_unwind(AssertUnwindSafe(|| {
        let ns = if node_count == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(nodes, node_count) }
        };
        let es = if edge_count == 0 {
            &[]
        } else {
            unsafe { slice::from_raw_parts(edges, edge_count) }
        };
        match run(ns, es, unsafe { &*options }) {
            Ok(value) => {
                unsafe {
                    *result = Box::into_raw(Box::new(value));
                }
                0
            }
            Err(code) => code,
        }
    }))
    .unwrap_or(2)
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn td_dagre_result_free(result: *mut TDDagreResult) {
    if !result.is_null() {
        unsafe {
            drop(Box::from_raw(result));
        }
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn td_dagre_result_node(
    result: *const TDDagreResult,
    index: usize,
    node: *mut TDNodeOutput,
) -> i32 {
    if result.is_null() || node.is_null() {
        return 0;
    }
    match unsafe { &*result }.nodes.get(index) {
        Some(value) => {
            unsafe {
                *node = *value;
            }
            1
        }
        None => 0,
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn td_dagre_result_edge(
    result: *const TDDagreResult,
    index: usize,
    edge: *mut TDEdgeOutput,
) -> i32 {
    if result.is_null() || edge.is_null() {
        return 0;
    }
    match unsafe { &*result }.edges.get(index) {
        Some(value) => {
            unsafe {
                *edge = value.0;
            }
            1
        }
        None => 0,
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn td_dagre_result_point(
    result: *const TDDagreResult,
    edge_index: usize,
    point_index: usize,
    point: *mut TDPoint,
) -> i32 {
    if result.is_null() || point.is_null() {
        return 0;
    }
    match unsafe { &*result }
        .edges
        .get(edge_index)
        .and_then(|e| e.1.get(point_index))
    {
        Some(value) => {
            unsafe {
                *point = *value;
            }
            1
        }
        None => 0,
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn td_dagre_result_size(
    result: *const TDDagreResult,
    size: *mut TDPoint,
) -> i32 {
    if result.is_null() || size.is_null() {
        return 0;
    }
    unsafe {
        *size = (*result).size;
    }
    1
}
