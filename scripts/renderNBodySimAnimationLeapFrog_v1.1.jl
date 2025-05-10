# Ensure required packages are installed (uncomment if needed)
# using Pkg
# Pkg.add(["GLMakie", "CSV", "DataFrames", "Colors", "ProgressMeter"])

# Load necessary libraries
using GLMakie
using CSV
using DataFrames
using Logging
using Colors
using Statistics
using ProgressMeter

# Configure Makie for better performance and rendering
GLMakie.activate!()

# --- Function: Calculate Velocities ---
function calculate_velocities(data::DataFrame)
    # Create new columns for velocity components and magnitude
    data[!, :VelX] = zeros(nrow(data))
    data[!, :VelY] = zeros(nrow(data))
    data[!, :VelZ] = zeros(nrow(data))
    data[!, :VelMagnitude] = zeros(nrow(data))
    
    # Group data by BodyID so we compute the differences per particle
    gdf = groupby(data, :BodyID)
    
    for subdf in gdf
        # Sort each subgroup by iteration to ensure correct ordering
        sort!(subdf, :Iteration)
        n = nrow(subdf)
        
        # Only compute differences if there are at least 2 iterations
        if n > 1
            # Compute differences in each coordinate for successive iterations
            vel_x = diff(subdf[!, :PosX])
            vel_y = diff(subdf[!, :PosY])
            vel_z = diff(subdf[!, :PosZ])
            
            # For iterations 2..n, assign the computed differences
            subdf[2:end, :VelX] = vel_x
            subdf[2:end, :VelY] = vel_y
            subdf[2:end, :VelZ] = vel_z
            
            # Compute the magnitude of the velocity vector
            subdf[2:end, :VelMagnitude] = sqrt.(vel_x.^2 .+ vel_y.^2 .+ vel_z.^2)
        end
    end
    return data
end

# --- Function: Calculate Precise Limits for 2D Projections ---
function calculate_precise_limits(data, iteration;
    dynamic::Bool = false,
    zoom_factor::Float64 = 0.5,
    # Valores por defecto estáticos para cada proyección:
    xy_xlims = (-6,6), xy_ylims = (-6,6),
    xz_xlims = (-5,5), xz_ylims = (-2,2),
    yz_xlims = (-2,2), yz_ylims = (-5,5))
    
    if dynamic
        # Filtrar los datos para la iteración actual
        iter_data = data[data.Iteration .== iteration, :]

        # Para la proyección XY:
        centroid_x = mean(iter_data.PosX)
        centroid_y = mean(iter_data.PosY)
        x_range = maximum(iter_data.PosX) - minimum(iter_data.PosX)
        y_range = maximum(iter_data.PosY) - minimum(iter_data.PosY)
        xy_xlims = (centroid_x - x_range * zoom_factor, centroid_x + x_range * zoom_factor)
        xy_ylims = (centroid_y - y_range * zoom_factor, centroid_y + y_range * zoom_factor)
        
        # Para la proyección XZ:
        # Usamos el mismo x que en XY y calculamos z dinámicamente
        centroid_z = mean(iter_data.PosZ)
        z_range = maximum(iter_data.PosZ) - minimum(iter_data.PosZ)
        # Se podría usar la misma xlims que en XY o calcularlos de nuevo; aquí reutilizamos:
        xz_xlims = xy_xlims  
        xz_ylims = (centroid_z - z_range * zoom_factor, centroid_z + z_range * zoom_factor)
        
        # Para la proyección YZ:
        # Usamos el mismo y que en XY y z dinámico
        yz_xlims = xy_ylims
        yz_ylims = xz_ylims
    end

    return (xy = (xy_xlims, xy_ylims),
            xz = (xz_xlims, xz_ylims),
            yz = (yz_xlims, yz_ylims))
end


# --- Function: Render Particle Projections (2D) ---
function render_particle_projections(data_path, output_path; manual_zoom_range=nothing)
    @info "Loading simulation data"
    data = CSV.read(data_path, DataFrame)

    # Calculate velocities
    @info "Calculating particle velocities"
    data = calculate_velocities(data)

    # Calculate velocity statistics (for color mapping)
    velocities = filter(!iszero, data.VelMagnitude)
    min_velocity = quantile(velocities, 0.05)
    max_velocity = quantile(velocities, 0.95)
    @info "Velocity range: $min_velocity to $max_velocity"

    # Set theme (adjust as needed)
    dark_latexfonts = merge(theme_latexfonts())
    set_theme!(dark_latexfonts)

    # Create figure with subplots for 3 projections
    fig = Figure(resolution = (1200, 400))
    ax_xy = Axis(fig[1, 1], xlabel = "X", ylabel = "Y", title = "XY Projection")
    ax_xz = Axis(fig[1, 2], xlabel = "X", ylabel = "Z", title = "XZ Projection")
    ax_yz = Axis(fig[1, 3], xlabel = "Y", ylabel = "Z", title = "YZ Projection")

    iterations = sort(unique(data.Iteration))
    total_iterations = length(iterations)

    # Progress meter for rendering
    p = Progress(total_iterations, desc="Rendering projections...", 
                 barglyphs=ProgressMeter.BarGlyphs("[=> ]"), 
                 barlen=50, 
                 color=:green)

    # Animation recording block
    record(fig, output_path, iterations; framerate = 60) do iteration
        # Clear previous data from each axis
        empty!(ax_xy)
        empty!(ax_xz)
        empty!(ax_yz)

#^------Calcular límites precisos para cada proyección------
        limits = calculate_precise_limits(data, iteration;
                        xy_xlims=(-6,6), xy_ylims=(-6,6),
                        xz_xlims=(-5,5), xz_ylims=(-2,2),
                        yz_xlims=(-2,2), yz_ylims=(-5,5))
#^-----------------------------------------------------------

#^------Calcular limites dinamicos para cada iteracion-------
#~        # Dentro de tu bucle de animación, para cada iteración:
#~        limits = calculate_precise_limits(data, iteration; dynamic=true)  # o false, según se necesite
#^------------------------------------------------------------

        xy_limits = limits.xy
        xz_limits = limits.xz
        yz_limits = limits.y
        xlims!(ax_xy, xy_limits[1][1], xy_limits[1][2])
        ylims!(ax_xy, xy_limits[2][1], xy_limits[2][2])
        xlims!(ax_xz, xz_limits[1][1], xz_limits[1][2])
        ylims!(ax_xz, xz_limits[2][1], xz_limits[2][2])
        xlims!(ax_yz, yz_limits[1][1], yz_limits[1][2])
        ylims!(ax_yz, yz_limits[2][1], yz_limits[2][2])

        # Filter data for the current iteration
        iter_data = data[data.Iteration .== iteration, :]

        # Prepare positions for each projection
        positions_xy = Point2f.(iter_data.PosX, iter_data.PosY)
        positions_xz = Point2f.(iter_data.PosX, iter_data.PosZ)
        positions_yz = Point2f.(iter_data.PosY, iter_data.PosZ)

        # Scatter plot for each projection with velocity-based coloration
        scatter!(ax_xy, positions_xy, 
            color = [RGBA(v/max_velocity, 0.2, 0.8, 0.8) for v in iter_data.VelMagnitude], 
            markersize = 8, 
            marker = :circle)

        scatter!(ax_xz, positions_xz, 
            color = [RGBA(v/max_velocity, 0.2, 0.8, 0.8) for v in iter_data.VelMagnitude], 
            markersize = 8, 
            marker = :circle)

        scatter!(ax_yz, positions_yz, 
            color = [RGBA(v/max_velocity, 0.2, 0.8, 0.8) for v in iter_data.VelMagnitude], 
            markersize = 8, 
            marker = :circle)
            
        next!(p)
    end
end

# --- Main Execution ---
let
    data_path = "C:\\Users\\feder\\projects\\cuNBSim\\data\\simulation_data.csv"
    output_path = "leap_frog2.mp4"
    render_particle_projections(data_path, output_path)
end
