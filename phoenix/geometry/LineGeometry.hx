package phoenix.geometry;

import luxe.Log.*;
import luxe.Vector;
import luxe.Color;

import phoenix.Batcher;
import phoenix.geometry.Geometry;

import luxe.options.GeometryOptions.LineGeometryOptions;

class LineGeometry extends Geometry {

    @:isVar public var p0(default,set) : Vector;
    @:isVar public var p1(default,set) : Vector;
    @:isVar public var color0(default,set) : Color;
    @:isVar public var color1(default,set) : Color;

    public function new( ?options : LineGeometryOptions ) {

        super(options);

            //must happen after super to unset the default
        primitive_type = PrimitiveType.lines;


        if(options == null) return;


        def(options.color, new Color());
        def(options.color0, options.color);
        def(options.color1, options.color);

        p0 = def(options.p0, new Vector());
        p1 = def(options.p1, new Vector(64,64)); //:todo: unit constant

        var vert0 = new Vertex( p0, options.color0 );
        var vert1 = new Vertex( p1, options.color1 );

            vert0.uv.uv0.set_uv(0,0);
            vert1.uv.uv0.set_uv(1,0);

        add(vert0);
        add(vert1);

    } //new

//Internal

    function set_p0(_p:Vector) : Vector {

        p0 = _p;

        if(vertices.length == 0) return p0;

        vertices[0].pos = p0;

        return p0 = _p;

    } //set_p0

    function set_p1(_p:Vector) : Vector {

        p1 = _p;

        if(vertices.length == 0) return p1;

        vertices[1].pos = p1;

        return p1 = _p;

    } //set_p1

    function set_color0(_c:Color) : Color {

        color0 = _c;

        if(vertices.length == 0) return color0;

        vertices[0].color = color0;

        return color0;

    } //set_color0

    function set_color1(_c:Color) : Color {

        color1 = _c;

        if(vertices.length == 0) return color1;

        vertices[1].color = color1;

        return color1;

    } //set_color1

} //LineGeometry
